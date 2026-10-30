// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#import <Foundation/Foundation.h>
#include "transcribe.h"
#include "transcribe/parakeet.h"
#include <iostream>
#include <string>
#include <vector>
#include <unistd.h>
#include <cmath>

// One JSON line per request/reply. Native library logs use stderr exclusively.
// The parent terminates this process to cancel; a bad GPU cannot crash the UI.
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 2 && std::string(argv[1]) == "--selftest") {
            std::cout << "Vorssaint dictation engine " << transcribe_version() << std::endl;
            return 0;
        }
        FILE *protocol = fdopen(dup(STDOUT_FILENO), "w");
        if (!protocol || dup2(STDERR_FILENO, STDOUT_FILENO) < 0) return 2;
        auto init = transcribe_init_backends_default();
        transcribe_session *session = nullptr;
        std::string loaded;
        std::string line;
        while (std::getline(std::cin, line)) {
            @autoreleasepool {
                NSMutableDictionary *reply = [NSMutableDictionary dictionary];
                NSData *data = [[NSString stringWithUTF8String:line.c_str()] dataUsingEncoding:NSUTF8StringEncoding];
                id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                NSDictionary *request = [object isKindOfClass:NSDictionary.class] ? object : nil;
                NSString *path = [request[@"model"] isKindOfClass:NSString.class] ? request[@"model"] : nil;
                NSString *audio = [request[@"audio"] isKindOfClass:NSString.class] ? request[@"audio"] : nil;
                transcribe_status status = init;
                NSString *command = [request[@"command"] isKindOfClass:NSString.class] ? request[@"command"] : @"transcribe";
                bool feed = [command isEqualToString:@"feed"], finalize = [command isEqualToString:@"finalize"], reset = [command isEqualToString:@"reset"];
                if ((!path && !feed && !finalize && !reset) || (![command isEqualToString:@"begin"] && !feed && !finalize && !reset && !audio)) {
                    reply[@"error"] = @"Invalid dictation request";
                } else if (status == TRANSCRIBE_OK) {
                    if (feed || finalize || reset) {
                        if (reset) {
                            if (session) transcribe_stream_reset(session);
                        } else if (!session || transcribe_stream_get_state(session) != TRANSCRIBE_STREAM_ACTIVE) {
                            reply[@"error"] = @"No active speech stream";
                        } else if (feed) {
                            NSString *encoded = [request[@"pcm"] isKindOfClass:NSString.class] ? request[@"pcm"] : nil;
                            NSData *pcm = encoded ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
                            if (!pcm || !pcm.length || pcm.length % sizeof(float) || pcm.length > 16000 * 4 * 2) {
                                reply[@"error"] = @"Invalid live audio chunk";
                            } else {
                                status = transcribe_stream_feed(session, (const float *)pcm.bytes, (int)(pcm.length / sizeof(float)), nullptr);
                            }
                        } else {
                            status = transcribe_stream_finalize(session, nullptr);
                            if (status == TRANSCRIBE_OK) {
                                transcribe_stream_text text;
                                transcribe_stream_text_init(&text);
                                status = transcribe_stream_get_text(session, &text);
                                if (status == TRANSCRIBE_OK) {
                                    reply[@"text"] = text.full_text ? [NSString stringWithUTF8String:text.full_text] : @"";
                                    reply[@"streaming"] = @YES;
                                }
                                const char *detected = transcribe_detected_language(session);
                                reply[@"language"] = detected ? [NSString stringWithUTF8String:detected] : @"";
                            }
                        }
                    } else {
                        bool cpu = [request[@"cpu"] boolValue];
                        std::string key = std::string(path.UTF8String) + (cpu ? ":cpu" : ":auto");
                        if (!session || loaded != key) {
                            transcribe_session_free(session);
                            session = nullptr;
                            loaded.clear();
                            transcribe_model_load_params params;
                            transcribe_model_load_params_init(&params);
                            if (cpu) params.backend = TRANSCRIBE_BACKEND_CPU;
                            status = transcribe_open(path.fileSystemRepresentation, &params, nullptr, &session);
                            if (status == TRANSCRIBE_OK) loaded = key;
                        }
                        if (status == TRANSCRIBE_OK) {
                            transcribe_run_params params;
                            transcribe_run_params_init(&params);
                            NSString *language = [request[@"language"] isKindOfClass:NSString.class] ? request[@"language"] : @"";
                            params.language = language.length ? language.UTF8String : nullptr;
                            if ([request[@"translate"] boolValue]) {
                                params.task = TRANSCRIBE_TASK_TRANSLATE;
                                params.target_language = "en";
                            }
                            NSArray *words = [request[@"vocabulary"] isKindOfClass:NSArray.class] ? request[@"vocabulary"] : @[];
                            std::vector<const char *> terms;
                            for (id word in words) if ([word isKindOfClass:NSString.class]) terms.push_back([word UTF8String]);
                            params.vocabulary = terms.data();
                            params.n_vocabulary = (int32_t)terms.size();
                            if ([command isEqualToString:@"begin"]) {
                                transcribe_stream_params stream;
                                transcribe_stream_params_init(&stream);
                                transcribe_parakeet_buffered_stream_ext buffered;
                                transcribe_parakeet_buffered_stream_ext_init(&buffered);
                                if (transcribe_model_accepts_ext_kind(transcribe_get_model(session), TRANSCRIBE_EXT_SLOT_STREAM,
                                                                     TRANSCRIBE_EXT_KIND_PARAKEET_BUFFERED_STREAM)) {
                                    // A trained balanced preset: less residual work at release,
                                    // without the accuracy loss of zero-lookahead streaming.
                                    buffered.left_ms = 5600; buffered.chunk_ms = 560; buffered.right_ms = 560;
                                    stream.family = &buffered.ext;
                                }
                                status = transcribe_stream_begin(session, &params, &stream);
                                reply[@"streaming"] = @(status == TRANSCRIBE_OK);
                            } else {
                                transcribe_stream_reset(session);
                                NSData *pcm = [NSData dataWithContentsOfFile:audio options:NSDataReadingMappedIfSafe error:nil];
                                if (!pcm || !pcm.length || pcm.length % sizeof(float) || pcm.length > 16000ULL * 4 * 3600) {
                                    reply[@"error"] = @"Invalid audio: expected 16 kHz mono float32 PCM, at most one hour";
                                } else {
                                    status = transcribe_run(session, (const float *)pcm.bytes, (int)(pcm.length / sizeof(float)), &params);
                                }
                            }
                            if (status == TRANSCRIBE_OK && ![command isEqualToString:@"begin"] && !reply[@"error"]) {
                                const char *text = transcribe_full_text(session);
                                const char *detected = transcribe_detected_language(session);
                                reply[@"text"] = text ? [NSString stringWithUTF8String:text] : @"";
                                reply[@"language"] = detected ? [NSString stringWithUTF8String:detected] : language;
                            }
                        }
                    }
                }
                if (status == TRANSCRIBE_ERR_INPUT_TOO_SHORT) {
                    // Too little audio is a no-result outcome, not a failed engine.
                    reply[@"text"] = @"";
                } else if (status != TRANSCRIBE_OK) reply[@"error"] = [NSString stringWithUTF8String:transcribe_status_string(status)];
                NSData *encoded = [NSJSONSerialization dataWithJSONObject:reply options:0 error:nil];
                fwrite(encoded.bytes, 1, encoded.length, protocol);
                fputc('\n', protocol);
                fflush(protocol);
            }
        }
        // Skip GPU static destructors: the OS reclaims all model resources.
        _exit(0);
    }
}
