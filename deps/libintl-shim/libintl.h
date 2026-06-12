#pragma once

#ifdef __cplusplus
extern "C" {
#endif

static inline char *gettext(const char *msgid) {
    return (char *)(msgid ? msgid : "");
}

static inline char *dgettext(const char *domainname, const char *msgid) {
    (void)domainname;
    return gettext(msgid);
}

static inline char *dcgettext(const char *domainname, const char *msgid,
                              int category) {
    (void)category;
    return dgettext(domainname, msgid);
}

static inline char *ngettext(const char *msgid1, const char *msgid2,
                             unsigned long int n) {
    const char *msgid = n == 1 ? msgid1 : msgid2;
    return (char *)(msgid ? msgid : "");
}

static inline char *dngettext(const char *domainname, const char *msgid1,
                              const char *msgid2, unsigned long int n) {
    (void)domainname;
    return ngettext(msgid1, msgid2, n);
}

static inline char *dcngettext(const char *domainname, const char *msgid1,
                               const char *msgid2, unsigned long int n,
                               int category) {
    (void)category;
    return dngettext(domainname, msgid1, msgid2, n);
}

static inline char *textdomain(const char *domainname) {
    return (char *)(domainname ? domainname : "");
}

static inline char *bindtextdomain(const char *domainname,
                                   const char *dirname) {
    (void)domainname;
    return (char *)(dirname ? dirname : "");
}

static inline char *bind_textdomain_codeset(const char *domainname,
                                            const char *codeset) {
    (void)domainname;
    return (char *)(codeset ? codeset : "");
}

#ifdef __cplusplus
}
#endif
