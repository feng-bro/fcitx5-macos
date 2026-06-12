#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void fcitx_free_string(char *s);

void fcitx_start(const char *locale);
void fcitx_stop(void);
void fcitx_reload(void);
void fcitx_setup_i18n_c(void);

void *fcitx_create_input_context(const char *app_id, const char *accent_color);
void fcitx_destroy_input_context(void *context);
char *fcitx_process_key(void *context, uint32_t unicode, uint32_t modifiers,
                        uint16_t keycode, bool is_release, bool is_password,
                        const char *surrounding_text, uint32_t cursor,
                        uint32_t anchor);
char *fcitx_commit_composition(void *context);
void fcitx_focus_in(void *context, bool is_password);
void fcitx_focus_out(void *context);

char *fcitx_im_get_group_names(void);
char *fcitx_im_get_current_group_name(void);
void fcitx_im_set_current_group(const char *group_name);
char *fcitx_im_get_current_group(void);
int32_t fcitx_im_group_count_c(void);
void fcitx_im_add_to_current_group_c(const char *im_name);
char *fcitx_im_get_groups_c(void);
void fcitx_im_set_groups_c(const char *json);
char *fcitx_im_get_available_ims_c(void);
char *fcitx_im_get_current_im_name(void);
void fcitx_im_set_current_im(const char *im_name);
void fcitx_toggle_input_method_c(void);
char *fcitx_get_actions_c(void);
void fcitx_activate_action_by_id_c(int32_t id, bool hotkey);

char *fcitx_current_group_layout(void);
char *fcitx_get_addons_c(void);
char *fcitx_config_get_config_c(const char *uri);
bool fcitx_config_set_config_c(const char *uri, const char *json_patch);

#ifdef __cplusplus
}
#endif
