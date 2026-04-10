## version 1.0.4(2026-4-10)
- 新增命令：
 
	|  |  |  |  |  |  |
	|--|--|--|--|--|--|
	|patchelf|pkg-config|strip|gettext|strings|msgcat|
	|msgfilter|msggrep|size|msguniq|printf_gettext|recode-sr-latin|
	|envsubst|gettext.sh|msgattrib|msgcmp|msgconv|msgexec|
	|msgfmt|msgcomm|msgen|readelf|msgunfmt|ngettext|
	|printf_ngettext|xgettext|gawk|awk|gawkbug|crew-mvdir|
  	|addr2line|as|ar|c++filt|elfedit|ld|
	|nm|objcopy|objdump|ranlib|unrar|
- 修复文本内容复制到应用外失败的问题
- 更新sdk

## version 1.0.3(2026-2-11)
- 新增命令：

	|   |   |   |   | 
	|--|--|--|--|
	|idn2  | zma |sexp-conv| xz|
	|6tunnel|zmadec|unxz      |   xzcat|
	|lzcat   |    nettle-hash   | unlzma    |   xzdec|
	|lzmainfo|
- 更新命令
    修复groff不可用问题
    修复bzip2的不合理依赖
- 更新sdk
- 新增 cli 命令：推出基于 Cangjie Agent DSL 与 Cangjie Magic 构建的 AI 命令行助手，支持智能对话、代码生成、文档检索等核心功能，全面提升开发效率与交互体验。


## version 1.0.2(2025-12-27)
- 新增命令：
  |   |   |   |   | 
  |--|--|--|--|
  |tree   | hnpcli  |  cflow  |  bison|
- 更新命令
    hdc 升级5.1.0版本，修复无线连接依赖usb的不合理依赖
- 更新图标
- 优化手册及开源声明架构
- 增加 bash 解释器
- 更新llvm，增加编译签名功能


## version 1.0.1(2025-12-05)
- 新增命令：

|  |  |  |  |  |  |  |  |
|--|--|--|--|--|--|--|--|
|amdgpu-arch|clang-21|clang-sycl-linker|h2ph|lldb-argdumper|llvm-objdump|offload-arch|post-grohtml|
|scan-build-py|analyze-build|clang-check|cmake|h2xs|lldb-dap|llvm-pdbutil|perl|
|autoconf|clang-cl|corelist|hmaptool|lldb-instr|llvm-profdata|perl5.42.0|prove|
|autoheader|clang-cpp|cpack|ifnames|lldb-server|llvm-profgen|perlbug|ptar|
|autom4te|clang-extdef-mapping|cpan|instmodsh|llvm-ar|llvm-ranlib|perldoc|ptardiff|
|autoreconf|clang-format|ctest|intercept-build|llvm-cov|llvm-rc|perlivp|ptargrep|
|autoscan|clang-installapi|diagtool|irb|llvm-cxxfilt|llvm-readobj|perlthanks|racc|
|autoupdate|clang-linker-wrapper|egrep|json_pp|llvm-dlltool|llvm-size|piconv|rake|
|binary-sign-tool|clang-nvlink-wrapper|enc2xs|ld.lld|llvm-dwp|llvm-strings|pl2pm|rbs|
|bundle|clang-offload-bundler|encguess|ld64.lld|llvm-lib|llvm-strip|pod2html|rdbg|
|bundler|clang-offload-packager|erb|libnetcfg|llvm-mca|llvm-symbolizer|pod2man|rdoc|
|busybox|clang-refactor|gem|lld|llvm-ml|ninja|pod2text|ri|
|clang|clang-repl|git-clang-format|lld-link|llvm-nm|nvim|pod2usage|ruby|
|clang++|clang-scan-deps|grep|lldb|llvm-objcopy|nvptx-arch|podchecker|scan-build|
|pre-grohtml|scan-view|shasum|splain|streamzip|syntax_suggest|typeprof|wasm-ld|
|xmlwf|xsubpp|hdc|gdb|

- 新增命令手册功能，支持命令字和功能字查询
- 增加软件帮助页，包含软件信息、开源声明、隐私协议等
- 删除mini终端功能
- 优化图形界面样式
- 增加鸿蒙SDK安装方式


## version 1.0.0(2025-11-07)
- 新增命令：
	 |  |  |  |  |  |  |  |  | 
     |--|--|--|--|--|--|--|--|
	 |arp |diff |flex |grn |gzexe |m4 |refer |unexpand |
	 |bc |diff3 |fold |grodvi |hexdump |make |script |updatedb |
	 |bzip2 |dig |frcode |groff |host |mpstat |soelim |whereis |
	 |bzless |eqn |getopt |grolbp |iostat |nslookup |stty |xmlcatalog|
	 |colrm |fgrep |gperf |grops |less |pic |tbl |xmllint|
	 |column |find |gprof |grotty |locate |preconv |troff |xsltproc|
	|zcmp|zdiff|zipdetails|
- 新增迷你记事本、时间戳工具、Unicode转换工具、二维码生成器、系统资源查看器、进制转换工具、迷你终端