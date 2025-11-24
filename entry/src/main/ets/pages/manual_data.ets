export class CommandManualOption {
  paramName: string = '';
  description: string = '';
}

export class CommandManualData {
  name: string = '';
  description: string = '';
  syntax: string = '';
  options: CommandManualOption[] = [];
  examples: string[] = [];
  showDetails: boolean = false;
}

// 转换后的完整数据数组
const commandManualDataList: CommandManualData[] = [
  {
    name: 'arp',
    description: '用于查看和修改主机的ARP缓存表，该表包含IP地址与MAC地址的映射关系。',
    syntax: 'arp',
    options: [
      { paramName: '-a', description: 'Display (all) hosts' },
      { paramName: '-d', description: 'Delete ARP entry' },
      { paramName: '-s', description: 'Set new entry' },
      { paramName: '-v', description: 'Verbose' },
      { paramName: '-n', description: 'Don\'t resolve names' },
      { paramName: '-i', description: 'IF Network interface' },
      { paramName: '-D', description: 'Read HWADDR from IFACE' },
      { paramName: '-A,-p', description: 'AF Protocol family' },
      { paramName: '-H', description: 'HWTYPE Hardware address type' }
    ],
    examples: [
      'arp -a',
      'arp -d hostname',
      'arp -s hostname hwaddr'
    ],
    showDetails: false
  },
  {
    name: 'bc',
    description: '任意精度的计算器语言，支持基本的算术运算和复杂的数学函数。',
    syntax: 'bc [-sqlw] [FILE]...',
    options: [
      { paramName: '-q', description: 'Quiet' },
      { paramName: '-l', description: 'Load standard library' },
      { paramName: '-s', description: 'Be POSIX compatible' },
      { paramName: '-w', description: 'Warn if extensions are used' }
    ],
    examples: [
      'bc -l',
      'bc script.bc',
      'echo \'1+1\' | bc'
    ],
    showDetails: false
  },
  {
    name: 'bzip2',
    description: '高效的文件压缩工具，使用Burrows-Wheeler块排序文本压缩算法和霍夫曼编码。',
    syntax: 'bzip2 [flags and input files in any order]',
    options: [
      { paramName: '-h --help', description: 'print this message' },
      { paramName: '-d --decompress', description: 'force decompression' },
      { paramName: '-z --compress', description: 'force compression' },
      { paramName: '-k --keep', description: 'keep (don\'t delete) input files' },
      { paramName: '-f --force', description: 'overwrite existing output files' },
      { paramName: '-t --test', description: 'test compressed file integrity' },
      { paramName: '-c --stdout', description: 'output to standard out' },
      { paramName: '-q --quiet', description: 'suppress noncritical error messages' },
      { paramName: '-v --verbose', description: 'be verbose (a 2nd -v gives more)' },
      { paramName: '-L --license', description: 'display software version & license' },
      { paramName: '-V --version', description: 'display software version & license' },
      { paramName: '-1 to -9', description: 'set block size to 100k .. 900k' },
      { paramName: '--', description: 'treat all following arguments as files' }
    ],
    examples: [
      'bzip2 file.txt',
      'bzip2 -d file.bz2',
      'bzip2 -v file.txt'
    ],
    showDetails: false
  },
  {
    name: 'bzless',
    description: '用于查看bzip2压缩文件的过滤器，类似于less命令。',
    syntax: 'bzless files...',
    options: [],
    examples: [
      'bzless --help',
      'bzless -h'
    ],
    showDetails: false
  },
  {
    name: 'colrm',
    description: '用于从标准输入中删除指定的列，常用于文本处理。',
    syntax: 'colrm [startcol [endcol]]',
    options: [
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-V, --version', description: 'display version' }
    ],
    examples: [
      'colrm --help',
      'colrm -h',
      'colrm 5'
    ],
    showDetails: false
  },
  {
    name: 'column',
    description: '将输入文本格式化为多列输出，支持自动调整列宽和对齐。',
    syntax: 'column [options]',
    options: [
      { paramName: '-J, --json', description: 'output JSON' },
      { paramName: '-c, --columns <width>', description: 'output width' },
      { paramName: '-t, --table', description: 'create table' },
      { paramName: '-s, --separator <string>', description: 'field separator' },
      { paramName: '-o, --output-separator <string>', description: 'output separator' },
      { paramName: '-n, --table-name <name>', description: 'table name for JSON output' },
      { paramName: '-N, --table-columns <names>', description: 'table columns' },
      { paramName: '-R, --table-right <columns>', description: 'right align text in columns' },
      { paramName: '-T, --table-truncate <columns>', description: 'truncate text in columns' },
      { paramName: '-W, --table-wrap <columns>', description: 'wrap text in columns' },
      { paramName: '-E, --table-noextreme', description: 'do not print header and footer' },
      { paramName: '-H, --table-header-repeat', description: 'repeat header rows' },
      { paramName: '-O, --table-order <columns>', description: 'define column order' },
      { paramName: '-L, --table-left <columns>', description: 'left align text in columns' },
      { paramName: '-C, --table-center <columns>', description: 'center align text in columns' },
      { paramName: '-S, --table-sort <columns>', description: 'sort columns' },
      { paramName: '-K, --table-hide <columns>', description: 'hide columns' },
      { paramName: '-U, --table-unique <columns>', description: 'unique columns' },
      { paramName: '-D, --table-noheadings', description: 'do not print headings' },
      { paramName: '-F, --footer-repeat', description: 'repeat footer rows' },
      { paramName: '-x, --fillrows', description: 'fill rows before columns' },
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-V, --version', description: 'display version' },
      { paramName: '-l, --lines <number>', description: 'number of lines to read' },
      { paramName: '-r, --tree', description: 'display tree' }
    ],
    examples: [
      'column --help',
      'column -h',
      'column -t -s: /etc/passwd'
    ],
    showDetails: false
  },
  {
    name: 'diff',
    description: '用于比较两个或多个文件的差异，输出文件内容的不同之处。',
    syntax: 'diff [options]',
    options: [
      { paramName: '-i, --ignore-case', description: 'ignore case differences' },
      { paramName: '-E, --ignore-tab-expansion', description: 'ignore tab expansion' },
      { paramName: '-b, --ignore-space-change', description: 'ignore space changes' },
      { paramName: '-w, --ignore-all-space', description: 'ignore all space changes' },
      { paramName: '-B, --ignore-blank-lines', description: 'ignore blank lines' },
      { paramName: '-I, --ignore-matching-lines <regexp>', description: 'ignore lines matching regexp' },
      { paramName: '-a, --text', description: 'treat all files as text' },
      { paramName: '-c, -C, --context <n>', description: 'show n lines of context' },
      { paramName: '-u, -U, --unified <n>', description: 'show n lines of unified context' },
      { paramName: '-e, --ed', description: 'output an ed script' },
      { paramName: '-n, --rcs', description: 'output an RCS script' },
      { paramName: '-y, --side-by-side', description: 'output in two columns' },
      { paramName: '-W, --width <n>', description: 'set output width for side-by-side' },
      { paramName: '-p, --show-c-function', description: 'show which C function each change is in' },
      { paramName: '-F, --show-function-line <regexp>', description: 'show function line matching regexp' },
      { paramName: '-q, --brief', description: 'report only when files differ' },
      { paramName: '-r, --recursive', description: 'recursively compare any subdirectories found' },
      { paramName: '-N, --new-file', description: 'treat absent files as empty' },
      { paramName: '-x, --exclude <pattern>', description: 'exclude files that match pattern' },
      { paramName: '-X, --exclude-from <file>', description: 'exclude files that match any pattern in file' },
      { paramName: '-S, --starting-file <file>', description: 'start with file when comparing directories' },
      { paramName: '-P, --no-dereference', description: 'do not follow symbolic links' },
      { paramName: '-H, --speed-large-files', description: 'assume large files and many scattered small changes' },
      { paramName: '-l, --paginate', description: 'pass output through pr to paginate it' },
      { paramName: '-t, --expand-tabs', description: 'expand tabs to spaces in output' },
      { paramName: '-T, --initial-tab', description: 'make tabs line up by prepending a tab' },
      { paramName: '--tabsize <n>', description: 'set tab size to n spaces' },
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-V, --version', description: 'display version' }
    ],
    examples: [
      'diff file1.txt file2.txt',
      'diff -u file1.txt file2.txt',
      'diff -r dir1 dir2'
    ],
    showDetails: false
  },
  {
    name: 'diff3',
    description: '用于比较三个文件的差异，常用于合并不同版本的文件。',
    syntax: 'diff3 [options]',
    options: [
      { paramName: '-e', description: 'output an ed script' },
      { paramName: '-E', description: 'output an extended ed script' },
      { paramName: '-x', description: 'output a context ed script' },
      { paramName: '-X', description: 'output an extended context ed script' },
      { paramName: '-m', description: 'output merged file' },
      { paramName: '-A, --show-all', description: 'show all changes' },
      { paramName: '-3', description: 'show only changes from file3' },
      { paramName: '-i, --ignore-case', description: 'ignore case differences' },
      { paramName: '-a, --text', description: 'treat all files as text' },
      { paramName: '-T, --initial-tab', description: 'make tabs line up by prepending a tab' },
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-V, --version', description: 'display version' }
    ],
    examples: [
      'diff3 --help',
      'diff3 -h',
      'diff3 file1 file2 file3'
    ],
    showDetails: false
  },
  {
    name: 'dig',
    description: '域名系统(DNS)查询工具，用于查询DNS服务器获取域名解析信息。',
    syntax: 'dig [options]',
    options: [
      { paramName: '-h', description: 'display this help' },
      { paramName: '-v', description: 'print version number' },
      { paramName: '-q <name>', description: 'specify query name' },
      { paramName: '-t <type>', description: 'specify query type' },
      { paramName: '-x <addr>', description: 'reverse lookup' },
      { paramName: '-i', description: 'use IP6.INT for IPv6 reverse lookups' },
      { paramName: '-f <file>', description: 'batch mode' },
      { paramName: '-b <addr>', description: 'set source IP address' },
      { paramName: '-p <port#>', description: 'set port number' },
      { paramName: '-s <addr>', description: 'set EDNS0 source address' },
      { paramName: '-4', description: 'use IPv4 only' },
      { paramName: '-6', description: 'use IPv6 only' },
      { paramName: '-D', description: 'print DNSSEC data' },
      { paramName: '-k <keyfile>', description: 'specify tsig key file' },
      { paramName: '-y <name:key>', description: 'specify tsig key' },
      { paramName: '-n <ndots>', description: 'set search ndots' },
      { paramName: '-d', description: 'debug mode' },
      { paramName: '-L', description: 'print response in zone file format' },
      { paramName: '-r', description: 'disable recursion' },
      { paramName: '-R <retries>', description: 'set number of retries' },
      { paramName: '-A', description: 'abort on network errors' },
      { paramName: '-T', description: 'disable TCP/IP fallback' },
      { paramName: '-C', description: 'disable compression' },
      { paramName: '-o <filename>', description: 'output to file' },
      { paramName: '-O', description: 'do not buffer output' },
      { paramName: '-a', description: 'set AA flag in query' },
      { paramName: '-c <class>', description: 'specify query class' },
      { paramName: '-m', description: 'set memory usage' },
      { paramName: '-S <bufsize>', description: 'set EDNS0 buffer size' },
      { paramName: '-g', description: 'enable EDNS0' },
      { paramName: '-j', description: 'print response as JSON' }
    ],
    examples: [
      'dig example.com',
      'dig @8.8.8.8 example.com',
      'dig -x 8.8.8.8'
    ],
    showDetails: false
  },
  {
    name: 'flex',
    description: '词法分析器生成器，用于生成处理文本的程序，常与bison配合使用。',
    syntax: 'flex [options]',
    options: [
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-V, --version', description: 'display version' },
      { paramName: '-o <file>', description: 'specify output file' },
      { paramName: '-7', description: 'generate 7-bit scanner' },
      { paramName: '-8', description: 'generate 8-bit scanner (default)' },
      { paramName: '-F', description: 'generate fast scanner' },
      { paramName: '-f', description: 'generate fast scanner' },
      { paramName: '-X', description: 'generate scanner for 8-bit characters' },
      { paramName: '-I', description: 'generate interactive scanner' },
      { paramName: '-i', description: 'case-insensitive scanner' },
      { paramName: '-l', description: 'generate lex-compatible scanner' },
      { paramName: '-n', description: 'suppress #line directives' },
      { paramName: '-N', description: 'suppress #line directives' },
      { paramName: '-p', description: 'generate performance report' },
      { paramName: '-q', description: 'use table compression' },
      { paramName: '-s', description: 'suppress default rule' },
      { paramName: '-S <file>', description: 'use alternate skeleton file' },
      { paramName: '-t', description: 'write to stdout' },
      { paramName: '-v', description: 'print version number' },
      { paramName: '-w', description: 'suppress warnings' },
      { paramName: '-W <warning>', description: 'enable specific warning' },
      { paramName: '-B', description: 'generate backup files' },
      { paramName: '-P <prefix>', description: 'set scanner prefix' },
      { paramName: '-C <[aefm]>', description: 'set table compression options' },
      { paramName: '-T', description: 'run time performance report' },
      { paramName: '-R', description: 'generate reentrant scanner' },
      { paramName: '-D <name>', description: 'define name' },
      { paramName: '-L', description: 'print license' },
      { paramName: '-M', description: 'generate makefile dependencies' },
      { paramName: '-d', description: 'debug mode' },
      { paramName: '-E', description: 'generate scanner with echo' }
    ],
    examples: [
      'flex --help',
      'flex -h',
      'flex scanner.l'
    ],
    showDetails: false
  },
  {
    name: 'fold',
    description: '用于将长行文本折叠为指定宽度的短行，便于终端显示。',
    syntax: 'fold [options]',
    options: [
      { paramName: '-b, --bytes', description: 'count bytes rather than columns' },
      { paramName: '-s, --spaces', description: 'break at spaces' },
      { paramName: '-w, --width <width>', description: 'use width columns instead of 80' },
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-V, --version', description: 'display version' }
    ],
    examples: [
      'fold --help',
      'fold -h',
      'fold -w 80 file.txt'
    ],
    showDetails: false
  },
  {
    name: 'getopt',
    description: '用于解析命令行选项的工具，支持短选项和长选项。',
    syntax: 'getopt [options]',
    options: [
      { paramName: '-a, --alternative', description: 'allow long options starting with -' },
      { paramName: '-l, --longoptions <longopts>', description: 'define long options' },
      { paramName: '-n, --name <progname>', description: 'set program name for error messages' },
      { paramName: '-o, --options <opts>', description: 'define short options' },
      { paramName: '-q, --quiet', description: 'suppress error messages' },
      { paramName: '-Q, --quiet-output', description: 'suppress normal output' },
      { paramName: '-s, --shell <shell>', description: 'set shell type' },
      { paramName: '-T, --test', description: 'test for getopt compatibility' },
      { paramName: '-u, --unquoted', description: 'do not quote output' },
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-V, --version', description: 'display version' }
    ],
    examples: [
      'getopt --help',
      'getopt -h',
      'getopt -o ab:c:: -l long,longopt: -- "$@"'
    ],
    showDetails: false
  },
  {
    name: 'gperf',
    description: '生成完美哈希函数的工具，用于快速查找关键字。',
    syntax: 'gperf [options]',
    options: [
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-v, --version', description: 'display version' },
      { paramName: '-o, --output-file <file>', description: 'specify output file' },
      { paramName: '-a, --alternative', description: 'generate alternative implementation' },
      { paramName: '-c, --class-name <name>', description: 'set class name' },
      { paramName: '-C, --omit-struct-type', description: 'omit struct type' },
      { paramName: '-D, --omit-duplicates', description: 'omit duplicate entries' },
      { paramName: '-E, --enum', description: 'generate enum' },
      { paramName: '-F, --initializer-suffix <suffix>', description: 'set initializer suffix' },
      { paramName: '-G, --global-table', description: 'generate global table' },
      { paramName: '-H, --hash-function-name <name>', description: 'set hash function name' },
      { paramName: '-I, --includes', description: 'include standard headers' },
      { paramName: '-k, --slot-name <name>', description: 'set slot name' },
      { paramName: '-K, --keyword-name <name>', description: 'set keyword name' },
      { paramName: '-l, --language <lang>', description: 'set output language' },
      { paramName: '-L, --length-table', description: 'generate length table' },
      { paramName: '-m, --multi-case', description: 'case-insensitive comparison' },
      { paramName: '-M, --mask-table', description: 'generate mask table' },
      { paramName: '-n, --null-pointer', description: 'use NULL pointer' },
      { paramName: '-N, --lookup-function-name <name>', description: 'set lookup function name' },
      { paramName: '-O, --optimize', description: 'optimize for space' },
      { paramName: '-p, --pointer', description: 'use pointers' },
      { paramName: '-P, --pure-prototypes', description: 'generate pure prototypes' },
      { paramName: '-q, --quick', description: 'quick mode' },
      { paramName: '-Q, --question-mark', description: 'use ?:' },
      { paramName: '-r, --readonly-tables', description: 'make tables readonly' },
      { paramName: '-S, --switch', description: 'use switch statement' },
      { paramName: '-t, --struct-type', description: 'generate struct type' },
      { paramName: '-T, --template', description: 'generate template' },
      { paramName: '-U, --uppercase', description: 'uppercase identifiers' },
      { paramName: '-V, --verbose', description: 'verbose mode' },
      { paramName: '-W, --width <width>', description: 'set hash table width' },
      { paramName: '-x, --omit-extern', description: 'omit extern' },
      { paramName: '-X, --include-file <file>', description: 'include file' },
      { paramName: '-y, --compare-strncmp', description: 'use strncmp' },
      { paramName: '-Y, --compare-strcmp', description: 'use strcmp' }
    ],
    examples: [
      'gperf --help',
      'gperf -h',
      'gperf -o output.h input.gperf'
    ],
    showDetails: false
  },
  {
    name: 'gprof',
    description: '程序性能分析工具，用于分析程序的执行时间，找出性能瓶颈。',
    syntax: 'gprof [options]',
    options: [
      { paramName: '-a, --no-annotated-source', description: 'suppress annotated source listing' },
      { paramName: '-b, --brief', description: 'brief output' },
      { paramName: '-c, --exec-counts', description: 'output execution counts' },
      { paramName: '-C, --call-graph', description: 'output call graph' },
      { paramName: '-d, --debug', description: 'debug mode' },
      { paramName: '-e, --exclude-function <name>', description: 'exclude function' },
      { paramName: '-E, --exclude-file <name>', description: 'exclude file' },
      { paramName: '-f, --function-ordering', description: 'output function ordering' },
      { paramName: '-F, --file-ordering', description: 'output file ordering' },
      { paramName: '-g, --graph', description: 'output call graph' },
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-i, --file-info', description: 'output file information' },
      { paramName: '-I, --inhibit-annotated-source', description: 'suppress annotated source' },
      { paramName: '-j, --no-merge-functions', description: 'do not merge functions' },
      { paramName: '-J, --no-merge-files', description: 'do not merge files' },
      { paramName: '-k, --sum-time <key>:<value>', description: 'sum time' },
      { paramName: '-l, --line', description: 'output line information' },
      { paramName: '-L, --line-info', description: 'output line information' },
      { paramName: '-m, --min-count <count>', description: 'minimum count' },
      { paramName: '-M, --max-count <count>', description: 'maximum count' },
      { paramName: '-n, --no-static', description: 'exclude static functions' },
      { paramName: '-N, --include-function <name>', description: 'include function' },
      { paramName: '-O, --order-file <file>', description: 'order file' },
      { paramName: '-p, --flat-profile', description: 'output flat profile' },
      { paramName: '-P, --no-flat-profile', description: 'suppress flat profile' },
      { paramName: '-q, --quiet', description: 'quiet mode' },
      { paramName: '-Q, --no-call-graph', description: 'suppress call graph' },
      { paramName: '-r, --reverse-order', description: 'reverse order' },
      { paramName: '-R, --reverse-call-graph', description: 'reverse call graph' },
      { paramName: '-s, --sum-file <file>', description: 'sum file' },
      { paramName: '-S, --symbols', description: 'output symbols' },
      { paramName: '-t, --total-time', description: 'output total time' },
      { paramName: '-T, --traditional', description: 'traditional output' },
      { paramName: '-u, --unused-functions', description: 'output unused functions' },
      { paramName: '-U, --no-unused-functions', description: 'suppress unused functions' },
      { paramName: '-v, --version', description: 'display version' },
      { paramName: '-V, --verbose', description: 'verbose mode' },
      { paramName: '-w, --width <width>', description: 'set output width' },
      { paramName: '-W, --wide', description: 'wide output' },
      { paramName: '-x, --demangle', description: 'demangle symbols' },
      { paramName: '-X, --no-demangle', description: 'do not demangle symbols' },
      { paramName: '-y, --symbols-sort', description: 'sort symbols' },
      { paramName: '-Y, --symbols-no-sort', description: 'do not sort symbols' },
      { paramName: '-z, --show-zero-counts', description: 'show zero counts' },
      { paramName: '-Z, --no-show-zero-counts', description: 'suppress zero counts' }
    ],
    examples: [
      'gprof --help',
      'gprof -h',
      'gprof ./a.out gmon.out'
    ],
    showDetails: false
  },
  {
    name: 'groff',
    description: '文档格式化系统，用于将格式化的文本转换为各种输出格式。',
    syntax: 'groff [options]',
    options: [
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-v, --version', description: 'display version' },
      { paramName: '-a, --ascii', description: 'use ASCII output' },
      { paramName: '-c, --no-color', description: 'disable color output' },
      { paramName: '-C, --color', description: 'enable color output' },
      { paramName: '-d, --define <name>=<value>', description: 'define macro' },
      { paramName: '-D, --device <device>', description: 'set output device' },
      { paramName: '-e, --equations', description: 'process equations' },
      { paramName: '-E, --preprocess-only', description: 'preprocess only' },
      { paramName: '-f, --family <font>', description: 'set font family' },
      { paramName: '-F, --font-directory <dir>', description: 'set font directory' },
      { paramName: '-g, --grap', description: 'process grap code' },
      { paramName: '-G, --no-grap', description: 'disable grap processing' },
      { paramName: '-i, --include <dir>', description: 'add include directory' },
      { paramName: '-I, --include-dir <dir>', description: 'add include directory' },
      { paramName: '-k, --keep', description: 'keep intermediate files' },
      { paramName: '-K, --no-keep', description: 'remove intermediate files' },
      { paramName: '-l, --latin1', description: 'use Latin-1 input' },
      { paramName: '-L, --locale <locale>', description: 'set locale' },
      { paramName: '-m, --macro <name>', description: 'load macro package' },
      { paramName: '-M, --macro-directory <dir>', description: 'set macro directory' },
      { paramName: '-n, --page-number <num>', description: 'set starting page number' },
      { paramName: '-N, --no-number', description: 'disable page numbering' },
      { paramName: '-o, --output <file>', description: 'specify output file' },
      { paramName: '-O, --option <option>', description: 'pass option to postprocessor' },
      { paramName: '-p, --pic', description: 'process pic code' },
      { paramName: '-P, --no-pic', description: 'disable pic processing' },
      { paramName: '-q, --quiet', description: 'quiet mode' },
      { paramName: '-Q, --verbose', description: 'verbose mode' },
      { paramName: '-r, --resolution <dpi>', description: 'set resolution' },
      { paramName: '-R, --no-resolution', description: 'use default resolution' },
      { paramName: '-s, --safe', description: 'safe mode' },
      { paramName: '-S, --no-safe', description: 'disable safe mode' },
      { paramName: '-t, --tbl', description: 'process tbl code' },
      { paramName: '-T, --output-format <format>', description: 'set output format' },
      { paramName: '-u, --underline', description: 'enable underlining' },
      { paramName: '-U, --no-underline', description: 'disable underlining' },
      { paramName: '-w, --warning', description: 'enable warnings' },
      { paramName: '-W, --no-warning', description: 'disable warnings' },
      { paramName: '-x, --xroff', description: 'compatibility mode' },
      { paramName: '-X, --no-xroff', description: 'disable compatibility mode' },
      { paramName: '-y, --synctex', description: 'generate SyncTeX file' },
      { paramName: '-Y, --no-synctex', description: 'disable SyncTeX' },
      { paramName: '-z, --draft', description: 'draft mode' },
      { paramName: '-Z, --debug', description: 'debug mode' }
    ],
    examples: [
      'groff --help',
      'groff -h',
      'groff -man manpage.1 | less'
    ],
    showDetails: false
  },
  {
    name: 'hexdump',
    description: '以十六进制和ASCII格式显示文件内容，用于查看二进制文件。',
    syntax: 'hexdump [options]',
    options: [
      { paramName: '-b, --one-byte-octal', description: 'one-byte octal display' },
      { paramName: '-c, --one-byte-char', description: 'one-byte character display' },
      { paramName: '-C, --canonical', description: 'canonical hex+ASCII display' },
      { paramName: '-d, --two-byte-decimal', description: 'two-byte decimal display' },
      { paramName: '-e, --format <format>', description: 'format string' },
      { paramName: '-f, --format-file <file>', description: 'format file' },
      { paramName: '-H, --help', description: 'display this help' },
      { paramName: '-n, --length <length>', description: 'interpret only length bytes' },
      { paramName: '-o, --two-byte-octal', description: 'two-byte octal display' },
      { paramName: '-s, --skip <offset>', description: 'skip offset bytes' },
      { paramName: '-v, --no-squeeze', description: 'do not squeeze identical lines' },
      { paramName: '-V, --version', description: 'display version' },
      { paramName: '-x, --two-byte-hex', description: 'two-byte hexadecimal display' }
    ],
    examples: [
      'hexdump --help',
      'hexdump -h',
      'hexdump -C binaryfile.bin'
    ],
    showDetails: false
  },
  {
    name: 'host',
    description: '简单的DNS查询工具，用于查询域名的IP地址或反向查询。',
    syntax: 'host [options]',
    options: [
      { paramName: '-a, --all', description: 'display all records' },
      { paramName: '-c, --class <class>', description: 'query class' },
      { paramName: '-C, --check-names', description: 'check pointer and host names' },
      { paramName: '-d, --debug', description: 'print debug information' },
      { paramName: '-l, --list', description: 'list zone' },
      { paramName: '-m, --mx', description: 'display MX records' },
      { paramName: '-N, --ns', description: 'display NS records' },
      { paramName: '-r, --raw', description: 'display raw packets' },
      { paramName: '-R, --random', description: 'randomize name server order' },
      { paramName: '-s, --server <server>', description: 'use server' },
      { paramName: '-t, --type <type>', description: 'query type' },
      { paramName: '-v, --verbose', description: 'verbose output' },
      { paramName: '-w, --wait', description: 'wait forever' },
      { paramName: '-W, --wait-time <seconds>', description: 'wait time' },
      { paramName: '-4, --ipv4', description: 'use IPv4 only' },
      { paramName: '-6, --ipv6', description: 'use IPv6 only' },
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-V, --version', description: 'display version' }
    ],
    examples: [
      'host example.com',
      'host -t mx example.com',
      'host 8.8.8.8'
    ],
    showDetails: false
  },
  {
    name: 'iostat',
    description: '系统I/O统计工具，用于监控系统的磁盘I/O和CPU使用情况。',
    syntax: 'iostat [options]',
    options: [
      { paramName: '-c, --cpu', description: 'display CPU statistics' },
      { paramName: '-d, --disk', description: 'display disk statistics' },
      { paramName: '-g, --group <grpname>', description: 'display statistics for disk group' },
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-k, --kilobytes', description: 'display in kilobytes per second' },
      { paramName: '-m, --megabytes', description: 'display in megabytes per second' },
      { paramName: '-N, --no-summary', description: 'exclude summary statistics' },
      { paramName: '-n, --nfs', description: 'display NFS statistics' },
      { paramName: '-p, --partition <dev>', description: 'display statistics for partition' },
      { paramName: '-r, --io-rate', description: 'display I/O rate statistics' },
      { paramName: '-s, --summary', description: 'display summary statistics' },
      { paramName: '-t, --time', description: 'display timestamp' },
      { paramName: '-T, --time-format <format>', description: 'set time format' },
      { paramName: '-V, --version', description: 'display version' },
      { paramName: '-x, --extended', description: 'display extended statistics' },
      { paramName: '-y, --first', description: 'exclude first report' },
      { paramName: '-z, --no-zeros', description: 'exclude lines with zero statistics' },
      { paramName: '[interval [count]]', description: 'report interval and count' }
    ],
    examples: [
      'iostat --help',
      'iostat -h',
      'iostat 2 10'
    ],
    showDetails: false
  },
  {
    name: 'locate',
    description: '快速查找文件的工具，基于预构建的文件数据库进行搜索。',
    syntax: 'locate [options]',
    options: [
      { paramName: '-A, --all', description: 'only print entries that match all patterns' },
      { paramName: '-b, --basename', description: 'match only the base name' },
      { paramName: '-c, --count', description: 'print number of matches' },
      { paramName: '-d, --database <path>', description: 'use database at path' },
      { paramName: '-e, --existing', description: 'only print existing files' },
      { paramName: '-i, --ignore-case', description: 'ignore case differences' },
      { paramName: '-L, --follow', description: 'follow symbolic links' },
      { paramName: '-m, --mmap', description: 'use mmap instead of read' },
      { paramName: '-n, --limit <number>', description: 'limit number of matches' },
      { paramName: '-P, --nofollow', description: 'do not follow symbolic links' },
      { paramName: '-0, --null', description: 'separate output with null characters' },
      { paramName: '-S, --statistics', description: 'print statistics about database' },
      { paramName: '-t, --basename', description: 'match only the base name' },
      { paramName: '-U, --update', description: 'update database' },
      { paramName: '-u, --unknown', description: 'print unknown file types' },
      { paramName: '-v, --verbose', description: 'verbose mode' },
      { paramName: '-w, --wholename', description: 'match whole path name (default)' },
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-V, --version', description: 'display version' }
    ],
    examples: [
      'locate --help',
      'locate -h',
      'locate filename.txt'
    ],
    showDetails: false
  },
  {
    name: 'm4',
    description: '通用宏处理器，用于文本替换和宏扩展，常被其他工具使用。',
    syntax: 'm4 [options]',
    options: [
      { paramName: '-D, --define <name>=<value>', description: 'define macro' },
      { paramName: '-E, --fatal-warnings', description: 'treat warnings as errors' },
      { paramName: '-e, --interactive', description: 'interactive mode' },
      { paramName: '-F, --freeze-state <file>', description: 'freeze state to file' },
      { paramName: '-f, --force-frozen', description: 'force frozen state' },
      { paramName: '-G, --traditional', description: 'traditional mode' },
      { paramName: '-g, --gnu', description: 'GNU mode (default)' },
      { paramName: '-H, --help', description: 'display this help' },
      { paramName: '-I, --include <dir>', description: 'add include directory' },
      { paramName: '-L, --nesting-limit <limit>', description: 'set nesting limit' },
      { paramName: '-l, --load <file>', description: 'load frozen state from file' },
      { paramName: '-M, --error-output <file>', description: 'send errors to file' },
      { paramName: '-N, --no-predefined', description: 'no predefined macros' },
      { paramName: '-n, --line-directives', description: 'generate line directives' },
      { paramName: '-o, --output <file>', description: 'specify output file' },
      { paramName: '-P, --prefix-builtins', description: 'prefix built-in macros' },
      { paramName: '-p, --no-line-directives', description: 'no line directives' },
      { paramName: '-Q, --quiet', description: 'quiet mode' },
      { paramName: '-R, --random-seed <seed>', description: 'set random seed' },
      { paramName: '-r, --reload-state <file>', description: 'reload state from file' },
      { paramName: '-S, --synclines', description: 'generate synclines' },
      { paramName: '-s, --silent', description: 'silent mode' },
      { paramName: '-T, --trace <name>', description: 'trace macro' },
      { paramName: '-t, --debug', description: 'debug mode' },
      { paramName: '-U, --undefine <name>', description: 'undefine macro' },
      { paramName: '-u, --unload-state', description: 'unload state' },
      { paramName: '-V, --version', description: 'display version' },
      { paramName: '-v, --verbose', description: 'verbose mode' },
      { paramName: '-W, --warning <warning>', description: 'enable warning' },
      { paramName: '-w, --no-warnings', description: 'disable warnings' },
      { paramName: '-X, --dump-definitions <file>', description: 'dump definitions to file' },
      { paramName: '-x, --dump-macros <file>', description: 'dump macros to file' }
    ],
    examples: [
      'm4 --help',
      'm4 -h',
      'm4 input.m4 > output.txt'
    ],
    showDetails: false
  },
  {
    name: 'make',
    description: '自动化构建工具，用于根据Makefile中的规则编译和链接程序。',
    syntax: 'make [options]',
    options: [
      { paramName: '-b, -m', description: 'POSIX compatibility' },
      { paramName: '-B, --always-make', description: 'unconditionally make all targets' },
      { paramName: '-C, --directory <dir>', description: 'change to directory dir' },
      { paramName: '-d', description: 'print debugging information' },
      { paramName: '-e, --environment-overrides', description: 'environment variables override makefiles' },
      { paramName: '-f, --file <file>', description: 'read makefile from file' },
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-i, --ignore-errors', description: 'ignore errors from commands' },
      { paramName: '-I, --include-dir <dir>', description: 'search dir for included makefiles' },
      { paramName: '-j, --jobs <n>', description: 'allow n jobs at once' },
      { paramName: '-k, --keep-going', description: 'keep going when some targets can\'t be made' },
      { paramName: '-l, --load-average <n>', description: 'don\'t start new jobs if load average is at least n' },
      { paramName: '-L, --check-symlink-times', description: 'use symlink times for target files' },
      { paramName: '-n, --just-print', description: 'print commands but don\'t execute them' },
      { paramName: '-o, --old-file <file>', description: 'don\'t remake file' },
      { paramName: '-O, --output-sync <type>', description: 'synchronize output of parallel jobs' },
      { paramName: '-p, --print-data-base', description: 'print make\'s internal database' },
      { paramName: '-q, --question', description: 'don\'t run any commands; exit status says if up to date' },
      { paramName: '-r, --no-builtin-rules', description: 'disable built-in rules' },
      { paramName: '-R, --no-builtin-variables', description: 'disable built-in variables' },
      { paramName: '-s, --silent', description: 'don\'t print commands' },
      { paramName: '-S, --no-keep-going', description: 'turn off -k' },
      { paramName: '-t, --touch', description: 'touch targets instead of remaking them' },
      { paramName: '-v, --version', description: 'display version' },
      { paramName: '-w, --print-directory', description: 'print directory names as make enters and leaves them' },
      { paramName: '-W, --what-if <file>', description: 'pretend file was modified' },
      { paramName: '-X, --exclude <dir>', description: 'exclude directory from search' }
    ],
    examples: [
      'make',
      'make install',
      'make clean',
      'make -j4'
    ],
    showDetails: false
  },
  {
    name: 'mpstat',
    description: '多处理器统计工具，用于监控每个CPU核心的使用情况。',
    syntax: 'mpstat [options]',
    options: [
      { paramName: '-A, --all', description: 'display all statistics' },
      { paramName: '-I, --interrupts', description: 'display interrupts statistics' },
      { paramName: '-P, --cpu <cpu>', description: 'display statistics for specified CPU' },
      { paramName: '-S, --softirqs', description: 'display softirqs statistics' },
      { paramName: '-U, --cpu-utilization', description: 'display CPU utilization statistics' },
      { paramName: '-V, --version', description: 'display version' },
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '[interval [count]]', description: 'report interval and count' }
    ],
    examples: [
      'mpstat --help',
      'mpstat -h',
      'mpstat -P ALL 2 5'
    ],
    showDetails: false
  },
  {
    name: 'nslookup',
    description: 'DNS查询工具，用于查询域名解析信息，支持交互式操作。',
    syntax: 'nslookup [options]',
    options: [
      { paramName: '-debug', description: 'debug mode' },
      { paramName: '-d2', description: 'more debug information' },
      { paramName: '-silent', description: 'silent mode' },
      { paramName: '-timeout <sec>', description: 'set timeout' },
      { paramName: '-retry <num>', description: 'set number of retries' },
      { paramName: '-port <port>', description: 'set port number' },
      { paramName: '-querytype <type>', description: 'set query type' },
      { paramName: '-queryclass <class>', description: 'set query class' },
      { paramName: '-vc', description: 'use virtual circuit' },
      { paramName: '-fail', description: 'fail on error' },
      { paramName: '-nodebug', description: 'disable debug mode' },
      { paramName: '-nod2', description: 'disable debug level 2' },
      { paramName: '-nosilent', description: 'disable silent mode' },
      { paramName: '-retry <num>', description: 'set number of retries' },
      { paramName: '-port <port>', description: 'set port number' },
      { paramName: '-querytype <type>', description: 'set query type' },
      { paramName: '-queryclass <class>', description: 'set query class' },
      { paramName: '-novc', description: 'disable virtual circuit' },
      { paramName: '-nofail', description: 'don\'t fail on error' },
      { paramName: '-version', description: 'display version' },
      { paramName: '-help', description: 'display help' }
    ],
    examples: [
      'nslookup example.com',
      'nslookup example.com 8.8.8.8',
      'nslookup -type=mx example.com'
    ],
    showDetails: false
  },
  {
    name: 'script',
    description: '用于记录终端会话的工具，将所有输入和输出保存到指定文件。',
    syntax: 'script [options]',
    options: [
      { paramName: '-a, --append', description: 'append to file' },
      { paramName: '-c, --command <command>', description: 'run command rather than interactive shell' },
      { paramName: '-e, --exit', description: 'exit on command exit' },
      { paramName: '-f, --flush', description: 'flush output after each write' },
      { paramName: '-q, --quiet', description: 'quiet mode' },
      { paramName: '-t, --timing <file>', description: 'output timing data to file' },
      { paramName: '-V, --version', description: 'display version' },
      { paramName: '-h, --help', description: 'display this help' }
    ],
    examples: [
      'script --help',
      'script -h',
      'script session.log'
    ],
    showDetails: false
  },
  {
    name: 'unexpand',
    description: '将文件中的空格转换为制表符，可指定转换规则',
    syntax: 'unexpand [-fa][-t N] [FILE]...',
    options: [
      { paramName: '-a', description: 'Convert all blanks' },
      { paramName: '-f', description: 'Convert only leading blanks' },
      { paramName: '-t N', description: 'Tabstops every N chars' },
      { paramName: '-h, --help', description: 'display this help' }
    ],
    examples: [
      'unexpand file.txt',
      'unexpand -a document.txt',
      'unexpand -t 4 sourcecode.c',
      'unexpand -f -t 8 input.txt > output.txt'
    ],
    showDetails: false
  },
  {
    name: 'updatedb',
    description: '更新系统文件位置数据库（供locate命令快速查询文件）',
    syntax: 'updatedb [--findoptions=\'options\'] [--localpaths=\'dirs\'] [--netpaths=\'dirs\'] [--prunepaths=\'dirs\'] [--prunefs=\'fs\'] [--output=dbfile] [--netuser=user] [--localuser=user] [--dbformat] [--version] [--help]',
    options: [
      { paramName: '--findoptions=\'-option1 -option2...\'', description: 'Specify options for find command' },
      { paramName: '--localpaths=\'dir1 dir2...\'', description: 'Specify local directories to search' },
      { paramName: '--netpaths=\'dir1 dir2...\'', description: 'Specify network directories to search' },
      { paramName: '--prunepaths=\'dir1 dir2...\'', description: 'Specify directories to exclude from search' },
      { paramName: '--prunefs=\'fs1 fs2...\'', description: 'Specify filesystem types to exclude' },
      { paramName: '--output=dbfile', description: 'Specify output database file path' },
      { paramName: '--netuser=user', description: 'Specify user for network directory search' },
      { paramName: '--localuser=user', description: 'Specify user for local directory search' },
      { paramName: '--dbformat', description: 'Specify database format' },
      { paramName: '--version', description: 'Display version information' },
      { paramName: '--help', description: 'Display help information' },
      { paramName: '-h, --help', description: 'display this help' }
    ],
    examples: [
      'updatedb',
      'updatedb --output=/var/lib/mlocate/mlocate.db',
      'updatedb --prunepaths=\'/tmp /var/tmp\'',
      'updatedb --localpaths=\'/home /usr\' --prunefs=\'nfs tmpfs\''
    ],
    showDetails: false
  },
  {
    name: 'whereis',
    description: '查找指定命令的二进制文件、源代码文件及对应手册页位置',
    syntax: 'whereis [options] [-BMS <dir>... -f] <name>',
    options: [
      { paramName: '-b', description: 'Search only for binaries' },
      { paramName: '-B <dirs>', description: 'Define binaries lookup path' },
      { paramName: '-f', description: 'Terminate <dirs> argument list' },
      { paramName: '-g', description: 'Interpret name as glob (pathnames pattern)' },
      { paramName: '-l', description: 'Output effective lookup paths' },
      { paramName: '-h, --help', description: 'display this help' },
      { paramName: '-M <dirs>', description: 'Define manual pages lookup path' },
      { paramName: '-S <dirs>', description: 'Define source files lookup path' }
    ],
    examples: [
      'whereis ls',
      'whereis -b python',
      'whereis -B /usr/local/bin -f gcc',
      'whereis -l'
    ],
    showDetails: false
  },
  {
    name: 'xmllint',
    description: '对 XML 文件进行解析、验证、格式化及语法检查的工具',
    syntax: 'xmllint [options] XMLfiles ...',
    options: [
      { paramName: '--version', description: 'Display the version of the XML library used' },
      { paramName: '--debug', description: 'Dump a debug tree of the in-memory document' },
      { paramName: '--shell', description: 'Run a navigating shell' },
      { paramName: '--debugent', description: 'Debug the entities defined in the document' },
      { paramName: '--copy', description: 'Test the internal copy implementation' },
      { paramName: '--recover', description: 'Output what was parsable on broken XML documents' },
      { paramName: '--huge', description: 'Remove any internal arbitrary parser limits' },
      { paramName: '--noent', description: 'Substitute entity references by their value' },
      { paramName: '--noenc', description: 'Ignore any encoding specified inside the document' },
      { paramName: '--noout', description: 'Don\'t output the result tree' },
      { paramName: '--path \'paths\'', description: 'Provide a set of paths for resources' },
      { paramName: '--load-trace', description: 'Print trace of all external entities loaded' },
      { paramName: '--nonet', description: 'Refuse to fetch DTDs or entities over network' },
      { paramName: '--nocompact', description: 'Do not generate compact text nodes' },
      { paramName: '--htmlout', description: 'Output results as HTML' },
      { paramName: '--nowrap', description: 'Do not put HTML doc wrapper' },
      { paramName: '--valid', description: 'Validate the document in addition to standard well-formed check' },
      { paramName: '--postvalid', description: 'Do a posteriori validation, i.e after parsing' },
      { paramName: '--dtdvalid URL', description: 'Do a posteriori validation against a given DTD' },
      { paramName: '--dtdvalidfpi FPI', description: 'Same as --dtdvalid but name the DTD with a Public Identifier' },
      { paramName: '--quiet', description: 'Be quiet when succeeded' },
      { paramName: '-h, --help', description: 'display this help' }
    ],
    examples: [
      'xmllint document.xml',
      'xmllint --valid --noout config.xml',
      'xmllint --format input.xml > output.xml',
      'xmllint --nonet --dtdvalid http://example.com/dtd.dtd data.xml',
      'xmllint --shell document.xml'
    ],
    showDetails: false
  },
  {
    name: 'xsltproc',
    description: '使用 XSLT 样式表将 XML 文件转换为其他格式（如 HTML、TXT）',
    syntax: 'xsltproc [options] stylesheet file...',
    options: [
      { paramName: '--version', description: 'Display version information' },
      { paramName: '--debug', description: 'Enable debugging output' },
      { paramName: '--novalid', description: 'Skip DTD validation of input documents' },
      { paramName: '--xmlout', description: 'Force XML output even if HTML is detected' },
      { paramName: '--htmlout', description: 'Force HTML output' },
      { paramName: '--encoding encoding', description: 'Specify output encoding' },
      { paramName: '--param name expression', description: 'Pass a parameter to the stylesheet (string values must be quoted)' },
      { paramName: '--stringparam name value', description: 'Pass a (parameter, UTF8 string value) pair' },
      { paramName: '--path \'paths\'', description: 'Provide a set of paths for resources' },
      { paramName: '--nonet', description: 'Refuse to fetch DTDs or entities over network' },
      { paramName: '--nowrite', description: 'Refuse to write to any file or resource' },
      { paramName: '--nomkdir', description: 'Refuse to create directories' },
      { paramName: '--writesubtree path', description: 'Allow file write only within the specified path subtree' },
      { paramName: '--catalogs', description: 'Use SGML catalogs from $SGML_CATALOG_FILES (default: XML Catalogs from file:///etc/xml/catalog)' },
      { paramName: '--xinclude', description: 'Do XInclude processing on document input' },
      { paramName: '--xincludestyle', description: 'Do XInclude processing on stylesheets' },
      { paramName: '--load-trace', description: 'Print trace of all external entities loaded' },
      { paramName: '--profile, --norman', description: 'Dump profiling information' },
      { paramName: '-h, --help', description: 'display this help' }
    ],
    examples: [
      'xsltproc style.xsl data.xml',
      'xsltproc --output result.html transform.xsl input.xml',
      'xsltproc --stringparam title \'My Document\' style.xsl content.xml',
      'xsltproc --nonet --catalogs stylesheet.xsl document.xml',
      'xsltproc --xinclude transform.xsl data.xml'
    ],
    showDetails: false
  },
  {
    name: 'zcmp',
    description: '直接对比两个压缩文件的字节内容，无需手动解压',
    syntax: 'zcmp [OPTION]... FILE1 [FILE2]',
    options: [
      { paramName: '-b, --print-bytes', description: 'Print differing bytes' },
      { paramName: '-i, --ignore-initial=N', description: 'Ignore first N bytes' },
      { paramName: '-i, --ignore-initial=N1:N2', description: 'Ignore first N1 bytes of FILE1 and N2 bytes of FILE2' },
      { paramName: '-l, --list', description: 'List all differing bytes' },
      { paramName: '-n, --bytes=N', description: 'Compare only first N bytes' },
      { paramName: '-s, --quiet, --silent', description: 'Suppress all output' },
      { paramName: '-v, --version', description: 'Display version information' },
      { paramName: '-h, --help', description: 'display this help' }
    ],
    examples: [
      'zcmp file1.gz file2.gz',
      'zcmp data.gz',
      'zcmp -l archive1.gz archive2.gz',
      'zcmp -n 1000 log1.gz log2.gz',
      'zcmp --silent report1.gz report2.gz && echo \'Files are identical\''
    ],
    showDetails: false
  },
  {
    name: 'zdiff',
    description: '对比两个压缩文件的文本内容差异，输出逐行对比结果',
    syntax: 'zdiff [OPTION]... FILE1 [FILE2]',
    options: [
      { paramName: '-q, --brief', description: 'Report only whether files differ' },
      { paramName: '-s, --report-identical-files', description: 'Report when files are identical' },
      { paramName: '-c, -C NUM, --context[=NUM]', description: 'Output NUM (default 3) lines of context' },
      { paramName: '-u, -U NUM, --unified[=NUM]', description: 'Output NUM (default 3) lines of unified context' },
      { paramName: '-i, --ignore-case', description: 'Ignore case differences in file contents' },
      { paramName: '-w, --ignore-all-space', description: 'Ignore all whitespace' },
      { paramName: '-b, --ignore-space-change', description: 'Ignore changes in the amount of whitespace' },
      { paramName: '-B, --ignore-blank-lines', description: 'Ignore blank lines' },
      { paramName: '-r, --recursive', description: 'Recursively compare any subdirectories found' },
      { paramName: '-N, --new-file', description: 'Treat absent files as empty' },
      { paramName: '-a, --text', description: 'Treat all files as text' },
      { paramName: '-v, --version', description: 'Display version information' },
      { paramName: '-h, --help', description: 'display this help' }
    ],
    examples: [
      'zdiff report1.gz report2.gz',
      'zdiff -u log1.gz log2.gz',
      'zdiff -q data1.gz data2.gz',
      'zdiff -r dir1/ dir2/',
      'zdiff --report-identical-files file.gz'
    ],
    showDetails: false
  },
  {
    name: 'stty',
    description: '配置和查看终端设备的设置',
    syntax: 'stty [-a|g] [-F DEVICE] [SETTING]...',
    options: [
      { paramName: '-F DEVICE', description: 'Open device instead of stdin' },
      { paramName: '-a', description: 'Print all current settings in human-readable form' },
      { paramName: '-g', description: 'Print in stty-readable form' },
      { paramName: 'speed', description: 'Set terminal baud rate (e.g., 9600, 115200)' },
      { paramName: 'csN', description: 'Set character size to N bits (5, 6, 7, 8)' },
      { paramName: 'parity', description: 'Set parity checking (even, odd, none)' },
      { paramName: 'stopb', description: 'Set number of stop bits (1, 2)' },
      { paramName: 'echo', description: 'Enable echoing of input characters' },
      { paramName: '-echo', description: 'Disable echoing of input characters' },
      { paramName: 'icanon', description: 'Enable canonical mode (line-by-line input)' },
      { paramName: '-icanon', description: 'Disable canonical mode (character-by-character input)' },
      { paramName: 'sane', description: 'Set terminal to sane settings' },
      { paramName: '-h, --help', description: 'display this help' }
    ],
    examples: [
      'stty',
      'stty -a',
      'stty -g',
      'stty -F /dev/ttyUSB0 115200 cs8 -parity',
      'stty echo',
      'stty -echo',
      'stty sane'
    ],
    showDetails: false
  }
];

export default commandManualDataList;