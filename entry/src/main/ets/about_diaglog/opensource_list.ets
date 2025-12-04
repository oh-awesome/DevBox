/*
 * Copyright (c) 2025 OpenHarmonyPCDeveloper
 *
 * Licensed under the Mulan PSL v2 (the "License");
 * You can use this software according to the terms and conditions of the Mulan PSL v2.
 * You may obtain a copy of Mulan PSL v2 at:
 *
 *          http://license.coscl.org.cn/MulanPSL2
 *
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
 * EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
 * MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 * See the Mulan PSL v2 for more details.
 */

import { LicenseType } from '../common/Constants';
import { OpenSourceNoticeMetaData } from './opensource_info';

const ossComponentsList: OpenSourceNoticeMetaData[] = [
  {
    "name": "autoconf",
    "license": LicenseType.GPL_V3L,
    "source": "https://savannah.gnu.org/projects/autoconf",
    "licenseFile": "about_autoconf_opensource.html",
    "showLicense": false
  },
  {
    "name": "bind",
    "license": LicenseType.MPL_2,
    "source": "https://www.isc.org/bind/",
    "licenseFile": "about_bind_opensource.html",
    "showLicense": false
  },
  {
    "name": "binutils",
    "license": LicenseType.GPL_V2L,
    "source": "https://ftp.gnu.org/gnu/binutils/",
    "licenseFile": "about_binutils_opensource.html",
    "showLicense": false
  },
  {
    "name": "busybox",
    "license": LicenseType.GPL_V2L,
    "source": "https://github.com/mirror/busybox",
    "licenseFile": "about_busybox_opensource.html",
    "showLicense": false
  },
  {
    "name": "bzip2",
    "license": LicenseType.BZIP_2,
    "source": "https://sourceware.org/bzip2/",
    "licenseFile": "about_bzip2_opensource.html",
    "showLicense": false
  },
  {
    "name": "cmake",
    "license": LicenseType.BSD_3,
    "source": "https://github.com/Kitware/CMake",
    "licenseFile": "about_cmake_opensource.html",
    "showLicense": false
  },
  {
    "name": "colrm",
    "license": LicenseType.GPL_V2L,
    "source": "https://github.com/util-linux/util-linux",
    "licenseFile": "about_colrm_opensource.html",
    "showLicense": false
  },
  {
    "name": "column",
    "license": LicenseType.GPL_V2L,
    "source": "https://github.com/util-linux/util-linux",
    "licenseFile": "about_column_opensource.html",
    "showLicense": false
  },
  {
    "name": "diffutils",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/gnu/diffutils/",
    "licenseFile": "about_diffutils_opensource.html",
    "showLicense": false
  },
  {
    "name": "expat",
    "license": LicenseType.MIT,
    "source": "https://libexpat.github.io/",
    "licenseFile": "about_expat_opensource.html",
    "showLicense": false
  },
  {
    "name": "findutils",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/gnu/findutils/",
    "licenseFile": "about_findutils_opensource.html",
    "showLicense": false
  },
  {
    "name": "flex",
    "license": LicenseType.BSD_4,
    "source": "https://github.com/westes/flex",
    "licenseFile": "about_flex_opensource.html",
    "showLicense": false
  },
  {
    "name": "gdb",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/pub/gnu/gdb/",
    "licenseFile": "about_gdb_opensource.html",
    "showLicense": false
  },
  {
    "name": "gmp",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/pub/gnu/gmp/",
    "licenseFile": "about_gdb_opensource.html",
    "showLicense": false
  },
  {
    "name": "gettext",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/pub/gnu/gettext/",
    "licenseFile": "about_gettext_opensource.html",
    "showLicense": false
  },
  {
    "name": "gperf",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/pub/gnu/gperf/",
    "licenseFile": "about_gperf_opensource.html",
    "showLicense": false
  },
  {
    "name": "gprof",
    "license": LicenseType.GPL_V3L,
    "source": "https://sourceware.org/binutils/docs/gprof/",
    "licenseFile": "about_gprof_opensource.html",
    "showLicense": false
  },
  {
    "name": "grep",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/gnu/grep/",
    "licenseFile": "about_grep_opensource.html",
    "showLicense": false
  },
  {
    "name": "groff",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/gnu/groff/",
    "licenseFile": "about_groff_opensource.html",
    "showLicense": false,
    isNeedHide: true
  },
  {
    "name": "gzip",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/gnu/gzip/",
    "licenseFile": "about_gzip_opensource.html",
    "showLicense": false
  },
  {
    "name": "less",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/gnu/less/",
    "licenseFile": "about_less_opensource.html",
    "showLicense": false
  },
  {
    "name": "libedit",
    "license": LicenseType.BSD_3,
    "source": "https://thrysoee.dk/editline/",
    "licenseFile": "about_libedit_opensource.html",
    "showLicense": false
  },
  {
    "name": "libexpat",
    "license": LicenseType.MIT,
    "source": "https://libexpat.github.io/",
    "licenseFile": "about_libexpat_opensource.html",
    "showLicense": false
  },
  {
    "name": "libffi",
    "license": LicenseType.MIT,
    "source": "https://sourceware.org/libffi/",
    "licenseFile": "about_libffi_opensource.html",
    "showLicense": false
  },
  {
    "name": "libiconv",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/pub/gnu/libiconv/",
    "licenseFile": "about_libiconv_opensource.html",
    "showLicense": false
  },
  {
    "name": "libunistring",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/pub/gnu/libunistring/",
    "licenseFile": "about_libunistring_opensource.html",
    "showLicense": false
  },
  {
    "name": "libuv",
    "license": LicenseType.MIT,
    "source": "https://github.com/libuv/libuv",
    "licenseFile": "about_libuv_opensource.html",
    "showLicense": false
  },
  {
    "name": "libxml",
    "license": LicenseType.MIT,
    "source": "https://gitlab.gnome.org/GNOME/libxml2/",
    "licenseFile": "about_libxml_opensource.html",
    "showLicense": false
  },
  {
    "name": "libxslt",
    "license": LicenseType.MIT,
    "source": "https://gitlab.gnome.org/GNOME/libxslt",
    "licenseFile": "about_libxslt_opensource.html",
    "showLicense": false
  },
  {
    "name": "libyaml",
    "license": LicenseType.MIT,
    "source": "https://github.com/yaml/libyaml",
    "licenseFile": "about_libyaml_opensource.html",
    "showLicense": false
  },
  {
    "name": "llvm",
    "license": LicenseType.APACHE_2,
    "source": "https://github.com/llvm/llvm-project",
    "licenseFile": "about_llvm_opensource.html",
    "showLicense": false
  },
  {
    "name": "lz4",
    "license": LicenseType.GPL_V2L,
    "source": "https://github.com/lz4/lz4",
    "licenseFile": "about_lz4_opensource.html",
    "showLicense": false
  },
  {
    "name": "m4",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/pub/gnu/m4/",
    "licenseFile": "about_m4_opensource.html",
    "showLicense": false
  },
  {
    "name": "make",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/pub/gnu/make/",
    "licenseFile": "about_make_opensource.html",
    "showLicense": false
  },
  {
    "name": "mpfr",
    "license": LicenseType.GPL_V3L,
    "source": "https://ftp.gnu.org/pub/gnu/mpfr/",
    "licenseFile": "about_mpfr_opensource.html",
    "showLicense": false
  },
  {
    "name": "ncurses",
    "license": LicenseType.MIT,
    "source": "https://github.com/mirror/ncurses",
    "licenseFile": "about_ncurses_opensource.html",
    "showLicense": false
  },
  {
    "name": "neovim",
    "license": LicenseType.APACHE_2,
    "source": "https://github.com/neovim/neovim",
    "licenseFile": "about_neovim_opensource.html",
    "showLicense": false
  },
  {
    "name": "nghttp",
    "license": LicenseType.MIT,
    "source": "https://github.com/nghttp2/nghttp2/",
    "licenseFile": "about_nghttp_opensource.html",
    "showLicense": false
  },
  {
    "name": "ninja",
    "license": LicenseType.APACHE_2,
    "source": "https://github.com/ninja-build/ninja",
    "licenseFile": "about_ninja_opensource.html",
    "showLicense": false
  },
  {
    "name": "openssl",
    "license": LicenseType.APACHE_2,
    "source": "https://github.com/openssl/openssl",
    "licenseFile": "about_openssl_opensource.html",
    "showLicense": false
  },
  {
    "name": "pcre2",
    "license": LicenseType.BSD_3,
    "source": "https://github.com/PCRE2Project/pcre2",
    "licenseFile": "about_pcre2_opensource.html",
    "showLicense": false
  },
  {
    "name": "perl",
    "license": LicenseType.GPL_V1L,
    "source": "https://github.com/Perl/perl5",
    "licenseFile": "about_perl_opensource.html",
    "showLicense": false
  },
  {
    "name": "ruby",
    "license": LicenseType.BSD_2,
    "source": "https://github.com/ruby/ruby",
    "licenseFile": "about_ruby_opensource.html",
    "showLicense": false
  },
  {
    "name": "utils_linux",
    "license": LicenseType.GPL_V2L,
    "source": "https://github.com/util-linux/util-linux",
    "licenseFile": "about_utils_linux_opensource.html",
    "showLicense": false
  },
  {
    "name": LicenseType.VIM,
    "license": LicenseType.VIM,
    "source": "https://github.com/vim/vim",
    "licenseFile": "about_vim_opensource.html",
    "showLicense": false
  },
  {
    "name": "whereis",
    "license": LicenseType.GPL_V2L,
    "source": "https://github.com/util-linux/util-linux",
    "licenseFile": "about_whereis_opensource.html",
    "showLicense": false
  },
  {
    "name": "xz",
    "license": LicenseType.BSD_0,
    "source": "https://tukaani.org/xz/",
    "licenseFile": "about_xz_opensource.html",
    "showLicense": false
  },
  {
    "name": "zlib",
    "license": LicenseType.ZLIB,
    "source": "https://github.com/madler/zlib",
    "licenseFile": "about_zlib_opensource.html",
    "showLicense": false
  }
]

export default ossComponentsList;