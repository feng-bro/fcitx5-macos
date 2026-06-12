#include "fcitx-capi.h"

#include <cstdlib>
#include <cstring>
#include <string>

#include "fcitx.h"
#include "config/config-public.h"
#include "../macosfrontend/macosfrontend.h"
#include "../keycode/keycode.h"

namespace {

char *copyString(const std::string &s) {
    auto *result = static_cast<char *>(std::malloc(s.size() + 1));
    if (!result) {
        return nullptr;
    }
    std::memcpy(result, s.c_str(), s.size() + 1);
    return result;
}

fcitx::MacosInputContext *asInputContext(void *context) {
    return static_cast<fcitx::MacosInputContext *>(context);
}

} // namespace

extern "C" {

void fcitx_free_string(char *s) { std::free(s); }

void fcitx_start(const char *locale) { start_fcitx_thread(locale); }

void fcitx_stop(void) { stop_fcitx_thread(); }

void fcitx_reload(void) { reload(); }

void fcitx_setup_i18n_c(void) { setupI18N(); }

void *fcitx_create_input_context(const char *app_id,
                                 const char *accent_color) {
    return with_fcitx([=](Fcitx &fcitx) -> void * {
        return fcitx.frontend()->createInputContextPtr(
            app_id ? app_id : "", accent_color ? accent_color : "");
    });
}

void fcitx_destroy_input_context(void *context) {
    if (!context) {
        return;
    }
    with_fcitx([=](Fcitx &fcitx) {
        fcitx.frontend()->destroyInputContext(asInputContext(context));
    });
}

char *fcitx_process_key(void *context, uint32_t unicode, uint32_t modifiers,
                        uint16_t keycode, bool is_release, bool is_password,
                        const char *surrounding_text, uint32_t cursor,
                        uint32_t anchor) {
    if (!context) {
        return copyString("{}");
    }
    const fcitx::Key parsedKey =
        osx_key_to_fcitx_key(unicode, modifiers, keycode);
    return copyString(with_fcitx([=](Fcitx &fcitx) {
        return fcitx.frontend()->keyEvent(
            asInputContext(context), parsedKey, is_release, is_password,
            surrounding_text ? surrounding_text : "", cursor, anchor);
    }));
}

char *fcitx_commit_composition(void *context) {
    if (!context) {
        return copyString("{}");
    }
    return copyString(with_fcitx([=](Fcitx &fcitx) {
        return fcitx.frontend()->commitComposition(asInputContext(context));
    }));
}

void fcitx_focus_in(void *context, bool is_password) {
    if (!context) {
        return;
    }
    with_fcitx([=](Fcitx &fcitx) {
        fcitx.frontend()->focusIn(asInputContext(context), is_password);
    });
}

void fcitx_focus_out(void *context) {
    if (!context) {
        return;
    }
    with_fcitx([=](Fcitx &fcitx) {
        fcitx.frontend()->focusOut(asInputContext(context));
    });
}

char *fcitx_im_get_group_names(void) { return copyString(imGetGroupNames()); }

char *fcitx_im_get_current_group_name(void) {
    return copyString(imGetCurrentGroupName());
}

void fcitx_im_set_current_group(const char *group_name) {
    imSetCurrentGroup(group_name ? group_name : "");
}

char *fcitx_im_get_current_group(void) {
    return copyString(imGetCurrentGroup());
}

int32_t fcitx_im_group_count_c(void) { return imGroupCount(); }

void fcitx_im_add_to_current_group_c(const char *im_name) {
    imAddToCurrentGroup(im_name ? im_name : "");
}

char *fcitx_im_get_groups_c(void) { return copyString(imGetGroups()); }

void fcitx_im_set_groups_c(const char *json) {
    imSetGroups(json ? json : "[]");
}

char *fcitx_im_get_available_ims_c(void) {
    return copyString(imGetAvailableIMs());
}

char *fcitx_im_get_current_im_name(void) {
    return copyString(imGetCurrentIMName());
}

void fcitx_im_set_current_im(const char *im_name) {
    imSetCurrentIM(im_name ? im_name : "");
}

void fcitx_toggle_input_method_c(void) { toggleInputMethod(); }

char *fcitx_get_actions_c(void) { return copyString(getActions()); }

void fcitx_activate_action_by_id_c(int32_t id, bool hotkey) {
    activateActionById(id, hotkey);
}

char *fcitx_current_group_layout(void) {
    return copyString(get_current_group_layout());
}

char *fcitx_get_addons_c(void) { return copyString(getAddons()); }

char *fcitx_config_get_config_c(const char *uri) {
    return copyString(getConfig(uri ? uri : ""));
}

bool fcitx_config_set_config_c(const char *uri, const char *json_patch) {
    return setConfig(uri ? uri : "", json_patch ? json_patch : "{}");
}

} // extern "C"
