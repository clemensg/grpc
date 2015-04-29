/*
 *
 * Copyright 2015, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#import "GRPCWrappedCall.h"
#import <Foundation/Foundation.h>
#include <grpc/grpc.h>
#include <grpc/byte_buffer.h>
#include <grpc/support/alloc.h>
#import "GRPCCompletionQueue.h"
#import "NSDictionary+GRPC.h"
#import "NSData+GRPC.h"
#import "NSError+GRPC.h"

@implementation GRPCOpSendMetadata{
  void(^_handler)(void);
  grpc_metadata *_send_metadata;
  size_t _count;
}

- (instancetype)init {
  return [self initWithMetadata:nil handler:nil];
}

- (instancetype)initWithMetadata:(NSDictionary *)metadata handler:(void (^)(void))handler {
  if (self = [super init]) {
    _send_metadata = [metadata grpc_metadataArray];
    _count = metadata.count;
    _handler = handler;
  }
  return self;
}

- (void)getOp:(grpc_op *)op {
  op->op = GRPC_OP_SEND_INITIAL_METADATA;
  op->data.send_initial_metadata.count = _count;
  op->data.send_initial_metadata.metadata = _send_metadata;
}

- (void (^)(void))opProcessor {
  return ^{
    gpr_free(_send_metadata);
    if (_handler) {
      _handler();
    }
  };
}

@end

@implementation GRPCOpSendMessage{
  void(^_handler)(void);
  grpc_byte_buffer *_byte_buffer;
}

- (instancetype)init {
  return [self initWithMessage:nil handler:nil];
}

- (instancetype)initWithMessage:(NSData *)message handler:(void (^)(void))handler {
  if (!message) {
    [NSException raise:NSInvalidArgumentException format:@"message cannot be null"];
  }
  if (self = [super init]) {
    _byte_buffer = [message grpc_byteBuffer];
    _handler = handler;
  }
  return self;
}

- (void)getOp:(grpc_op *)op {
  op->op = GRPC_OP_SEND_MESSAGE;
  op->data.send_message = _byte_buffer;
}

- (void (^)(void))opProcessor {
  return ^{
    gpr_free(_byte_buffer);
    if (_handler) {
      _handler();
    }
  };
}

@end

@implementation GRPCOpSendClose{
  void(^_handler)(void);
}

- (instancetype)init {
  return [self initWithHandler:nil];
}

- (instancetype)initWithHandler:(void (^)(void))handler {
  if (self = [super init]) {
    _handler = handler;
  }
  return self;
}

- (void)getOp:(grpc_op *)op {
  op->op = GRPC_OP_SEND_CLOSE_FROM_CLIENT;
}

- (void (^)(void))opProcessor {
  return ^{
    if (_handler) {
      _handler();
    }
  };
}

@end

@implementation GRPCOpRecvMetadata{
  void(^_handler)(NSDictionary *);
  grpc_metadata_array _recv_initial_metadata;
}

- (instancetype) init {
  return [self initWithHandler:nil];
}

- (instancetype) initWithHandler:(void (^)(NSDictionary *))handler {
  if (self = [super init]) {
    _handler = handler;
    grpc_metadata_array_init(&_recv_initial_metadata);
  }
  return self;
}

- (void)getOp:(grpc_op *)op {
  op->op = GRPC_OP_RECV_INITIAL_METADATA;
  op->data.recv_initial_metadata = &_recv_initial_metadata;
}

- (void (^)(void))opProcessor {
  return ^{
    NSDictionary *metadata = [NSDictionary
                              grpc_dictionaryFromMetadata:_recv_initial_metadata.metadata
                              count:_recv_initial_metadata.count];
    grpc_metadata_array_destroy(&_recv_initial_metadata);
    if (_handler) {
      _handler(metadata);
    }
  };
}

@end

@implementation GRPCOpRecvMessage{
  void(^_handler)(grpc_byte_buffer *);
  grpc_byte_buffer *_recv_message;
}

- (instancetype)init {
  return [self initWithHandler:nil];
}

- (instancetype)initWithHandler:(void (^)(grpc_byte_buffer *))handler {
  if (self = [super init]) {
    _handler = handler;
  }
  return self;
}

- (void)getOp:(grpc_op *)op {
  op->op = GRPC_OP_RECV_MESSAGE;
  op->data.recv_message = &_recv_message;
}

- (void (^)(void))opProcessor {
  return ^{
    if (_handler) {
      _handler(_recv_message);
    }
  };
}

@end

@implementation GRPCOpRecvStatus{
  void(^_handler)(NSError *);
  size_t _details_capacity;
  grpc_status _status;
}

- (instancetype) init {
  return [self initWithHandler:nil];
}

- (instancetype) initWithHandler:(void (^)(NSError *))handler {
  if (self = [super init]) {
    _handler = handler;
    _status.details = NULL;
    _details_capacity = 0;
    grpc_metadata_array_init(&_status.metadata);
  }
  return self;
}

- (void)getOp:(grpc_op *)op {
  op->op = GRPC_OP_RECV_STATUS_ON_CLIENT;
  op->data.recv_status_on_client.status = &_status.status;
  op->data.recv_status_on_client.status_details = &_status.details;
  op->data.recv_status_on_client.status_details_capacity = &_details_capacity;
  op->data.recv_status_on_client.trailing_metadata = &_status.metadata;
}

- (void (^)(void))opProcessor {
  return ^{
    if (_handler) {
      NSError *error = [NSError grpc_errorFromStatus:&_status];
      grpc_metadata_array_destroy(&_status.metadata);
      _handler(error);
    }
  };
}

@end

@implementation GRPCWrappedCall{
  grpc_call *_call;
  GRPCCompletionQueue *_queue;
}

- (instancetype)init {
  return [self initWithChannel:nil method:nil host:nil];
}

- (instancetype)initWithChannel:(GRPCChannel *)channel
                         method:(NSString *)method
                           host:(NSString *)host {
  if (!channel || !method || !host) {
    [NSException raise:NSInvalidArgumentException
                format:@"channel, method, and host cannot be nil."];
  }
  
  if (self = [super init]) {
    static dispatch_once_t initialization;
    dispatch_once(&initialization, ^{
      grpc_init();
    });
    
    _queue = [GRPCCompletionQueue completionQueue];
    if (!_queue) {
      return nil;
    }
    _call = grpc_channel_create_call(channel.unmanagedChannel, _queue.unmanagedQueue,
                                     method.UTF8String, host.UTF8String, gpr_inf_future);
    if (_call == NULL) {
      return nil;
    }
  }
  return self;
}

- (void)startBatchWithOperations:(NSArray *)operations {
  [self startBatchWithOperations:operations errorHandler:nil];
}

- (void)startBatchWithOperations:(NSArray *)operations errorHandler:(void (^)())errorHandler {
  NSMutableArray *opProcessors = [NSMutableArray array];
  size_t nops = operations.count;
  grpc_op *ops_array = gpr_malloc(nops * sizeof(grpc_op));
  size_t i = 0;
  for (id op in operations) {
    [op getOp:&ops_array[i++]];
    [opProcessors addObject:[op opProcessor]];
  }
  grpc_call_error error = grpc_call_start_batch(_call, ops_array, nops,
                                                (__bridge_retained void *)(^(grpc_op_error error){
    if (error != GRPC_OP_OK) {
      if (errorHandler) {
        errorHandler();
      } else {
        return;
      }
    }
    for (void(^processor)(void) in opProcessors) {
      processor();
    }
  }));
  
  if (error != GRPC_CALL_OK) {
    [NSException raise:NSInternalInconsistencyException
                format:@"A precondition for calling grpc_call_start_batch wasn't met"];
  }
}

- (void)cancel {
  grpc_call_cancel(_call);
}

- (void)dealloc {
  grpc_call_destroy(_call);
}

@end