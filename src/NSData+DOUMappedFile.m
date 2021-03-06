/* vim: set ft=objc fenc=utf-8 sw=2 ts=2 et: */
/*
 *  DOUAudioStreamer - A Core Audio based streaming audio player for iOS/Mac:
 *
 *      http://github.com/douban/DOUAudioStreamer
 *
 *  Copyright 2013 Douban Inc.  All rights reserved.
 *
 *  Use and distribution licensed under the BSD license.  See
 *  the LICENSE file for full text.
 *
 *  Authors:
 *      Chongyu Zhu <lembacon@gmail.com>
 *
 */

#import "NSData+DOUMappedFile.h"
#include <sys/types.h>
#include <sys/mman.h>

static NSMutableDictionary *get_size_map()
{
  static NSMutableDictionary *map = nil;

  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    map = [[NSMutableDictionary alloc] init];
  });

  return map;
}

static void mmap_deallocate(void *ptr, void *info)
{
  NSNumber *key = [NSNumber numberWithUnsignedLongLong:(uintptr_t)ptr];
  NSNumber *fileSize = nil;

  NSMutableDictionary *sizeMap = get_size_map();
  @synchronized(sizeMap) {
    fileSize = [sizeMap objectForKey:key];
    [sizeMap removeObjectForKey:key];
  }

  size_t size = [fileSize unsignedLongLongValue];
  munmap(ptr, size);
}

static CFAllocatorRef get_mmap_deallocator()
{
  static CFAllocatorRef deallocator = NULL;

  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    CFAllocatorContext context;
    bzero(&context, sizeof(context));
    context.deallocate = mmap_deallocate;

    deallocator = CFAllocatorCreate(kCFAllocatorDefault, &context);
  });

  return deallocator;
}

@implementation NSData (DOUMappedFile)

+ (instancetype)dataWithMappedContentsOfFile:(NSString *)path
{
  return [[self class] _dataWithMappedContentsOfFile:path modifiable:NO];
}

+ (instancetype)dataWithMappedContentsOfURL:(NSURL *)url
{
  return [[self class] dataWithMappedContentsOfFile:[url path]];
}

+ (instancetype)modifiableDataWithMappedContentsOfFile:(NSString *)path
{
  return [[self class] _dataWithMappedContentsOfFile:path modifiable:YES];
}

+ (instancetype)modifiableDataWithMappedContentsOfURL:(NSURL *)url
{
  return [[self class] modifiableDataWithMappedContentsOfFile:[url path]];
}

+ (instancetype)_dataWithMappedContentsOfFile:(NSString *)path modifiable:(BOOL)modifiable
{
  NSFileHandle *fileHandle = nil;
  if (modifiable) {
    fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:path];
  }
  else {
    fileHandle = [NSFileHandle fileHandleForReadingAtPath:path];
  }
  if (fileHandle == nil) {
    return nil;
  }

  int fd = [fileHandle fileDescriptor];
  if (fd < 0) {
    return nil;
  }

  off_t size = lseek(fd, 0, SEEK_END);
  if (size < 0) {
    return nil;
  }

  int protection = PROT_READ;
  if (modifiable) {
    protection |= PROT_WRITE;
  }

  void *address = mmap(NULL, size, protection, MAP_FILE | MAP_SHARED, fd, 0);
  if (address == MAP_FAILED) {
    return nil;
  }

  NSMutableDictionary *sizeMap = get_size_map();
  @synchronized(sizeMap) {
    [sizeMap setObject:[NSNumber numberWithUnsignedLongLong:size]
                forKey:[NSNumber numberWithUnsignedLongLong:(uintptr_t)address]];
  }

  return CFBridgingRelease(CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, (const UInt8 *)address, size, get_mmap_deallocator()));
}

- (void)synchronizeMappedFile
{
  NSNumber *key = [NSNumber numberWithUnsignedLongLong:(uintptr_t)[self bytes]];
  NSNumber *fileSize = nil;

  NSMutableDictionary *sizeMap = get_size_map();
  @synchronized(sizeMap) {
    fileSize = [sizeMap objectForKey:key];
  }

  if (fileSize == nil) {
    return;
  }

  size_t size = [fileSize unsignedLongLongValue];
  msync((void *)[self bytes], size, MS_SYNC | MS_INVALIDATE);
}

@end
