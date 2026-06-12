#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void swift_frontend_override_keyboard_layout(void);
void swift_frontend_set_status_item_text(const char *text);
void swift_frontend_set_status_item_mode(int32_t mode);
void swift_frontend_commit_async(const char *commit);
void swift_frontend_commit_and_set_preedit_async(const char *commit,
                                                 const char *preedit,
                                                 int32_t caret_pos,
                                                 int32_t dummy_preedit);
int32_t swift_frontend_get_caret_coordinates(int32_t follow_caret,
                                             double *out_values,
                                             int32_t out_count);
char *swift_frontend_get_selection(void);
void swift_frontend_free_string(char *s);

#ifdef __cplusplus
}
#endif
