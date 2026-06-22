#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTPEntryObjC : NSObject
@property (nonatomic) uint32_t objectId;
@property (nonatomic) uint32_t storageId;
@property (nonatomic) uint32_t parentId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL isFolder;
@property (nonatomic) uint64_t size;
@property (nonatomic) NSDate * _Nullable modified;
@end

@interface MTPBridge : NSObject
/// Detect and open the first MTP device. Returns NO and sets error on failure.
- (BOOL)openFirstDeviceWithError:(NSError **)error;
- (void)close;
- (nullable NSString *)deviceFriendlyName;
- (uint32_t)primaryStorageId;
- (uint64_t)freeSpaceBytes;
- (nullable NSArray<MTPEntryObjC *> *)listFolder:(uint32_t)parentId
                                        storageId:(uint32_t)storageId
                                            error:(NSError **)error;
- (BOOL)downloadObject:(uint32_t)objectId
                toPath:(NSString *)path
              progress:(void (^ _Nullable)(uint64_t sent, uint64_t total))progress
                 error:(NSError **)error;
- (uint32_t)uploadFile:(NSString *)path
              toParent:(uint32_t)parentId
             storageId:(uint32_t)storageId
              progress:(void (^ _Nullable)(uint64_t sent, uint64_t total))progress
                 error:(NSError **)error;     // returns new object id, 0 on failure
- (uint32_t)createFolder:(NSString *)name
                inParent:(uint32_t)parentId
               storageId:(uint32_t)storageId
                   error:(NSError **)error;    // returns new object id, 0 on failure
- (BOOL)deleteObject:(uint32_t)objectId error:(NSError **)error;
- (BOOL)renameObject:(uint32_t)objectId toName:(NSString *)name error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
