#import "MTPBridge.h"
#import <libmtp.h>
#import <unistd.h>
#import <signal.h>
#import <string.h>
#import <stdlib.h>
#import <sys/sysctl.h>

static NSError *mtpError(NSString *msg, int code) {
    return [NSError errorWithDomain:@"dev.aft.mtp" code:code
                           userInfo:@{NSLocalizedDescriptionKey: msg}];
}

// macOS's ptpcamerad / Image Capture claim Android MTP devices on connect and
// win the race against us, causing libusb_claim_interface() to fail with
// LIBUSB_ERROR_ACCESS (-3). SIP forbids disabling the launchd agent, so we kill
// the holders directly (fast, via syscall — no subprocess spawn) and retry the
// claim in a tight loop. They respawn via launchd but cannot steal a USB
// interface we already hold once we win the race.
static void killProcessNamed(const char *name) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) < 0 || len == 0) return;
    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(len);
    if (!procs) return;
    if (sysctl(mib, 4, procs, &len, NULL, 0) >= 0) {
        int count = (int)(len / sizeof(struct kinfo_proc));
        for (int i = 0; i < count; i++) {
            if (strcmp(procs[i].kp_proc.p_comm, name) == 0) {
                kill(procs[i].kp_proc.p_pid, SIGKILL);
            }
        }
    }
    free(procs);
}

static void releaseSystemPTPHolders(void) {
    killProcessNamed("ptpcamerad");
    killProcessNamed("mscamerad-xpc");
}

@implementation MTPEntryObjC @end

@implementation MTPBridge {
    LIBMTP_mtpdevice_t *_device;
    uint32_t _storageId;
}

+ (void)initialize { if (self == [MTPBridge class]) LIBMTP_Init(); }

- (BOOL)openFirstDeviceWithError:(NSError **)error {
    // Idempotent: open (and claim the USB interface) only once. libusb on macOS
    // does not reliably release the interface on close within the same process,
    // so close/reopen thrashing self-deadlocks with LIBUSB_ERROR_ACCESS (-3).
    // We keep the handle open and just re-read storage on subsequent calls,
    // which is how we notice the device becoming ready (unlocked/authorized).
    if (!_device) {
        // Must open UNCACHED: LIBMTP_Get_First_Device() opens a cached device on
        // which LIBMTP_Get_Files_And_Folders refuses to work ("cached device!").
        LIBMTP_raw_device_t *rawDevices = NULL;
        int numRaw = 0;
        LIBMTP_error_number_t err = LIBMTP_Detect_Raw_Devices(&rawDevices, &numRaw);
        if (err != LIBMTP_ERROR_NONE || numRaw < 1 || rawDevices == NULL) {
            free(rawDevices);
            if (error) *error = mtpError(@"Could not connect to device", 1);
            return NO;
        }
        // A phone is present. ptpcamerad keeps re-grabbing the interface (and
        // respawns via launchd), so evict it and retry the claim in a tight
        // loop until we win the race (we hold it once claimed).
        for (int attempt = 0; attempt < 75 && _device == NULL; attempt++) {
            releaseSystemPTPHolders();
            _device = LIBMTP_Open_Raw_Device_Uncached(&rawDevices[0]);
            if (_device == NULL) {
                usleep(40000); // 40ms; keep evicting ptpcamerad until we win
            }
        }
        free(rawDevices);
        if (!_device) {
            if (error) *error = mtpError(@"Could not connect to device", 1);
            return NO;
        }
    }
    LIBMTP_Get_Storage(_device, LIBMTP_STORAGE_SORTBY_NOTSORTED);
    _storageId = _device->storage ? _device->storage->id : 0;
    return YES;
}

- (void)close {
    if (_device) { LIBMTP_Release_Device(_device); _device = NULL; }
}

- (NSString *)deviceFriendlyName {
    if (!_device) return nil;
    char *n = LIBMTP_Get_Friendlyname(_device);
    if (!n) { n = LIBMTP_Get_Modelname(_device); }
    if (!n) return @"Android device";
    NSString *s = [NSString stringWithUTF8String:n]; free(n); return s;
}

- (uint32_t)primaryStorageId { return _storageId; }

- (uint64_t)freeSpaceBytes {
    if (!_device || !_device->storage) return 0;
    return _device->storage->FreeSpaceInBytes;
}

- (NSArray<MTPEntryObjC *> *)listFolder:(uint32_t)parentId
                              storageId:(uint32_t)storageId
                                  error:(NSError **)error {
    if (!_device) { if (error) *error = mtpError(@"No device", 2); return nil; }
    // Listing a storage's root requires the ROOT sentinel, not 0.
    uint32_t lookupParent = (parentId == 0) ? LIBMTP_FILES_AND_FOLDERS_ROOT : parentId;
    LIBMTP_file_t *files = LIBMTP_Get_Files_And_Folders(_device, storageId, lookupParent);
    NSMutableArray *out = [NSMutableArray array];
    LIBMTP_file_t *f = files;
    while (f) {
        MTPEntryObjC *e = [MTPEntryObjC new];
        e.objectId = f->item_id;
        e.storageId = f->storage_id;
        e.parentId = f->parent_id;
        e.name = f->filename ? [NSString stringWithUTF8String:f->filename] : @"";
        e.isFolder = (f->filetype == LIBMTP_FILETYPE_FOLDER);
        e.size = f->filesize;
        e.modified = f->modificationdate > 0
            ? [NSDate dateWithTimeIntervalSince1970:f->modificationdate] : nil;
        [out addObject:e];
        LIBMTP_file_t *next = f->next; free(f->filename); free(f); f = next;
    }
    return out;
}

static int progress_cb(uint64_t sent, uint64_t total, void const *data) {
    void (^block)(uint64_t, uint64_t) = (__bridge void (^)(uint64_t, uint64_t))data;
    if (block) block(sent, total);
    return 0;
}

- (BOOL)downloadObject:(uint32_t)objectId toPath:(NSString *)path
              progress:(void (^)(uint64_t, uint64_t))progress error:(NSError **)error {
    int r = LIBMTP_Get_File_To_File(_device, objectId, path.fileSystemRepresentation,
                                    progress ? progress_cb : NULL,
                                    (__bridge void *)progress);
    if (r != 0) { if (error) *error = mtpError(@"Could not copy file", 3); return NO; }
    return YES;
}

- (uint32_t)uploadFile:(NSString *)path toParent:(uint32_t)parentId
             storageId:(uint32_t)storageId
              progress:(void (^)(uint64_t, uint64_t))progress error:(NSError **)error {
    NSDictionary *attrs = [[NSFileManager defaultManager]
                           attributesOfItemAtPath:path error:nil];
    uint64_t fsize = [attrs[NSFileSize] unsignedLongLongValue];
    LIBMTP_file_t *f = LIBMTP_new_file_t();
    f->filename = strdup(path.lastPathComponent.UTF8String);
    f->filesize = fsize;
    f->filetype = LIBMTP_FILETYPE_UNKNOWN;
    // Writing to the storage root requires the ROOT sentinel, not 0.
    f->parent_id = (parentId == 0) ? LIBMTP_FILES_AND_FOLDERS_ROOT : parentId;
    f->storage_id = storageId;
    int r = LIBMTP_Send_File_From_File(_device, path.fileSystemRepresentation, f,
                                       progress ? progress_cb : NULL,
                                       (__bridge void *)progress);
    uint32_t newId = f->item_id;
    LIBMTP_destroy_file_t(f);
    if (r != 0) { if (error) *error = mtpError(@"Could not copy file", 4); return 0; }
    return newId;
}

- (uint32_t)createFolder:(NSString *)name inParent:(uint32_t)parentId
               storageId:(uint32_t)storageId error:(NSError **)error {
    char *cname = strdup(name.UTF8String);
    uint32_t rootParent = (parentId == 0) ? LIBMTP_FILES_AND_FOLDERS_ROOT : parentId;
    uint32_t newId = LIBMTP_Create_Folder(_device, cname, rootParent, storageId);
    free(cname);
    if (newId == 0) { if (error) *error = mtpError(@"Could not create folder", 5); }
    return newId;
}

- (BOOL)deleteObject:(uint32_t)objectId error:(NSError **)error {
    int r = LIBMTP_Delete_Object(_device, objectId);
    if (r != 0) { if (error) *error = mtpError(@"Error while deleting", 6); return NO; }
    return YES;
}

- (BOOL)renameObject:(uint32_t)objectId toName:(NSString *)name error:(NSError **)error {
    LIBMTP_file_t *f = LIBMTP_Get_Filemetadata(_device, objectId);
    if (!f) { if (error) *error = mtpError(@"Could not rename file", 7); return NO; }
    int r = LIBMTP_Set_File_Name(_device, f, name.UTF8String);
    LIBMTP_destroy_file_t(f);
    if (r != 0) { if (error) *error = mtpError(@"Could not rename file", 7); return NO; }
    return YES;
}
@end
