/**
 * 环境变量管理器
 * - 保留文件原始行（注释/alias/空行/其他脚本内容）
 * - 同名 export 变量用 : 合并展示，$VAR 自引用解析
 * - 多值变量可展开查看/编辑/排序/删除子项
 * - 保存时只修改/追加/删除 export 行，其他行原样保留
 * - 支持自定义环境变量文件，信息保存到应用沙箱
 * - 支持多文件间同步变量
 */
import { DevTheme } from '../common/DevTheme';
import { DevPageHeader, DevCard, DevChip, DevInput, DevToast, DevDialogPanel, DevConfirm, DevConfirmChoice, DevBtn } from '../common/component';
import { fileIo as fs, fileUri, picker, fileShare } from '@kit.CoreFileKit';

import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';




import preferences from '@ohos.data.preferences';
import { pasteboard } from '@kit.BasicServicesKit';

import Logger from '../utils/Logger';
import { DevEnvPaths } from '../utils/DevEnvPaths';

const TAG: string = '[EnvManager] ';
const HOME_PATH: string = '/storage/Users/currentUser';
const PREF_CUSTOM_FILES: string = 'env_custom_files';
const PREF_NAME_FILES: string = 'env_files_config';

/** 原始文件中的一行 */
class FileLine {
  text: string = '';
  lineNum: number = 0;
  isExport: boolean = false;
  exportName: string = '';
  exportValue: string = '';
  exportComment: string = '';   // 行内注释（引号外 " #..." 段：显示/编辑剥离，保存拼回——不进值也不丢）
  inManagedBlock: boolean = false;  // DevBox 托管块内（ohpcd devenv/devbox 标记块——保存时原样透传）
}

/** 展示用的合并条目 */
class EnvEntry {
  name: string = '';
  value: string = '';
  isMulti: boolean = false;
  expanded: boolean = false;
  lineNums: number[] = [];
  managed: boolean = false;  // DevBox 托管块内（PATH 块等——只读展示，编辑走对应语言页）
}

/** 文件源信息 */
class SourceInfo {
  id: string = '';        // 唯一标识，如 'zshrc', 'bashrc', 'custom_xxx'
  label: string = '';     // 显示名，如 '~/.zshrc'
  path: string = '';      // 文件路径
  isBuiltIn: boolean = true; // 是否内置文件
  missing: boolean = false;  // 磁盘文件不存在（其他应用删除等——用户反馈需可见标识）
}

@Entry
@Component
export struct EnvManager {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @State sources: SourceInfo[] = [];
  @State currentSourceId: string = 'zshrc';
  @State searchKeyword: string = '';
  @State filteredList: EnvEntry[] = [];
  @State hasUnsaved: boolean = false;
  @State editOrigName: string = '';
  @State isAddMode: boolean = true;
  @State deleteTargetName: string = '';
  @State saving: boolean = false;
  @State loading: boolean = true;
  @State expandedSet: string = '';
  @State showSyncDialog: boolean = false;
  @State showAddFileDialog: boolean = false;
  @State syncFromId: string = '';
  @State syncTargetIds: string = ''; // 逗号分隔
  @State modifiedSet: string = '';   // 逗号分隔已修改变量名
  @State expandedFile: string = '';  // 展开的配置文件 id
  @State selectedVar: string = '';   // 表格中选中的变量名
  @State addedSet: string = '';      // 逗号分隔新增变量名

  // 每个 source 的数据: sourceId -> 数据


  private editDialogCtrl: CustomDialogController | null = null;
  private deleteDialogCtrl: CustomDialogController | null = null;
  private syncDialogCtrl: CustomDialogController | null = null;
  private addFileDialogCtrl: CustomDialogController | null = null;
  private removeDialogCtrl: CustomDialogController | null = null;
  private context: common.UIAbilityContext | null = null;
  // 平行数组存储各 source 的数据
  private sourceIds: string[] = [];
  private fileLinesArr: FileLine[][] = [];
  private displayListArr: EnvEntry[][] = [];

  private getFileLines(id: string): FileLine[] {
    for (let i = 0; i < this.sourceIds.length; i++) {
      if (this.sourceIds[i] === id) return this.fileLinesArr[i];
    }
    return [];
  }

  private getDisplayList(id: string): EnvEntry[] {
    for (let i = 0; i < this.sourceIds.length; i++) {
      if (this.sourceIds[i] === id) return this.displayListArr[i];
    }
    return [];
  }

  private setFileLines(id: string, data: FileLine[]): void {
    for (let i = 0; i < this.sourceIds.length; i++) {
      if (this.sourceIds[i] === id) {
        this.fileLinesArr[i] = data;
        this.fileLinesArr = [...this.fileLinesArr]; // 触发响应式更新
        return;
      }
    }
    this.sourceIds.push(id);
    this.fileLinesArr.push(data);
    this.displayListArr.push([]);
  }

  private setDisplayList(id: string, data: EnvEntry[]): void {
    for (let i = 0; i < this.sourceIds.length; i++) {
      if (this.sourceIds[i] === id) {
        this.displayListArr[i] = data;
        this.displayListArr = [...this.displayListArr]; // 触发响应式更新
        return;
      }
    }
    this.sourceIds.push(id);
    this.fileLinesArr.push([]);
    this.displayListArr.push(data);
    this.displayListArr = [...this.displayListArr]; // 触发响应式更新
  }

  private markModified(name: string): void {
    const parts: string[] = this.modifiedSet.split(',');
    for (const p of parts) { if (p === name) return; }
    this.modifiedSet = this.modifiedSet.length > 0 ? this.modifiedSet + ',' + name : name;
  }

  private markAdded(name: string): void {
    this.markModified(name);
    const parts: string[] = this.addedSet.split(',');
    for (const p of parts) { if (p === name) return; }
    this.addedSet = this.addedSet.length > 0 ? this.addedSet + ',' + name : name;
  }

  private isModified(name: string): boolean {
    const parts: string[] = this.modifiedSet.split(',');
    for (const p of parts) { if (p === name) return true; }
    return false;
  }

  private isNew(name: string): boolean {
    const parts: string[] = this.addedSet.split(',');
    for (const p of parts) { if (p === name) return true; }
    return false;
  }

  private clearModified(): void {
    this.modifiedSet = '';
    this.addedSet = '';
  }

  private getModifiedCount(): number {
    let count: number = 0;
    const parts: string[] = this.modifiedSet.split(',');
    for (const p of parts) { if (p.length > 0) count++; }
    return count;
  }

  aboutToAppear(): void {
    Logger.info(TAG, 'env aboutToAppear 触发（切页重建验证）');
    this.context = getContext(this) as common.UIAbilityContext;
    this.loadSources();
    this.initPermissionAndLoad();
  }

  // ─── Source 管理 ─────────────────────────────────

  private loadSources(): void {
    const builtIn: SourceInfo[] = [
      { id: 'zshrc', label: '~/.zshrc', path: `${HOME_PATH}/.zshrc`, isBuiltIn: true, missing: false },
      { id: 'bashrc', label: '~/.bashrc', path: `${HOME_PATH}/.bashrc`, isBuiltIn: true, missing: false },
    ];
    // 从 preferences 加载自定义文件
    const customList: SourceInfo[] = this.loadCustomSources();
    this.sources = [...builtIn, ...customList];
    this.markMissing();
  }

  /** 标记磁盘上已不存在的文件（其他应用删除——卡片显示「已失效」标识；重进/刷新时重估） */
  private markMissing(): void {
    for (const s of this.sources) {
      // fs.accessSync 返回 boolean（不抛异常——误用 try/catch 曾致恒 false，真机 hilog 实证）
      s.missing = !fs.accessSync(s.path);
      if (s.missing) {
        Logger.info(TAG, `markMissing: ${s.label} path=${s.path} 已失效`);
      }
    }
    this.sources = [...this.sources];   // 触发列表重渲染
  }

  private loadCustomSources(): SourceInfo[] {
    if (!this.context) return [];
    const result: SourceInfo[] = [];
    try {
      const pref = preferences.getPreferencesSync(this.context, { name: PREF_NAME_FILES });
      const val = pref.getSync(PREF_CUSTOM_FILES, '');
      if (typeof val !== 'string' || val.length === 0) return result;
      // 格式: id1|label1|path1;id2|label2|path2
      const items: string[] = val.split(';');
      for (const item of items) {
        const parts: string[] = item.split('|');
        if (parts.length >= 3) {
          const si: SourceInfo = new SourceInfo();
          si.id = parts[0];
          si.label = parts[1];
          si.path = parts[2];
          si.isBuiltIn = false;
          result.push(si);
        }
      }
    } catch (e) {
      Logger.info(TAG, `loadCustomSources failed: ${JSON.stringify(e)}`);
    }
    return result;
  }

  private saveCustomSources(): void {
    if (!this.context) return;
    const parts: string[] = [];
    for (const s of this.sources) {
      if (!s.isBuiltIn) {
        parts.push(`${s.id}|${s.label}|${s.path}`);
      }
    }
    try {
      const pref = preferences.getPreferencesSync(this.context, { name: PREF_NAME_FILES });
      pref.putSync(PREF_CUSTOM_FILES, parts.join(';'));
      pref.flushSync();
    } catch (e) {
      Logger.info(TAG, `saveCustomSources failed: ${JSON.stringify(e)}`);
    }
  }

  addCustomSource(label: string, path: string): void {
    const id: string = `custom_${Date.now()}`;
    const si: SourceInfo = new SourceInfo();
    si.id = id;
    si.label = label;
    si.path = path;
    si.isBuiltIn = false;
    this.sources = [...this.sources, si];
    this.saveCustomSources();
    // 加载新文件数据
    this.loadSingleSource(si);
  }

  /** 移除自定义文件：三选项确认（DevConfirm.choice——AlertDialog 横排按钮） */
  private askRemoveFile(): void {
    const src = this.currentSource();
    const opts: DevConfirmChoice[] = [];
    const o0: DevConfirmChoice = { text: '取消' };
    const o1: DevConfirmChoice = { text: '仅移除' };
    const o2: DevConfirmChoice = { text: '删除文件', danger: true };
    opts.push(o0, o1, o2);
    DevConfirm.choice(`移除 ${src.label}`, '仅移除：应用中不再显示，磁盘保留。删除文件：磁盘一并删除（不可恢复）。',
      opts,
      (idx: number) => {
        if (idx === 1) {
          setTimeout(() => { this.removeCustomSource(src.id); this.expandedFile = ''; }, 50);
        } else if (idx === 2) {
          setTimeout(() => {
            this.removeCustomSourceAndDelete(src.id, src.path);
            this.expandedFile = '';
          }, 50);
        }
      });
  }

  /** 仅移除（应用列表不再显示，磁盘文件保留）+ 删除文件（连盘一起删） */
  private removeCustomSourceAndDelete(id: string, path: string): void {
    // HOME 守卫（防御性：只删主目录下文件）
    if (path.startsWith(HOME_PATH + '/')) {
      try {
        fs.unlinkSync(path);
        DevToast.ok(`已删除文件 ${path}`);
      } catch (e) {
        // 文件删除失败仍移除列表（半途状态最糟：列表在文件不在）
        DevToast.show(`文件删除失败（${e}），已仅从列表移除`);
      }
    } else {
      DevToast.show($r('app.string.env_manager_1'));
    }
    this.removeCustomSource(id);
  }

  removeCustomSource(id: string): void {
    const newList: SourceInfo[] = [];
    for (const s of this.sources) {
      if (s.id !== id) newList.push(s);
    }
    this.sources = [...newList];
    if (this.currentSourceId === id) {
      this.currentSourceId = this.sources.length > 0 ? this.sources[0].id : '';
    }
    this.saveCustomSources();
    this.applyFilter();
  }

  private currentSource(): SourceInfo {
    for (const s of this.sources) {
      if (s.id === this.currentSourceId) return s;
    }
    return this.sources.length > 0 ? this.sources[0] : new SourceInfo();
  }

  /** 当前文件在分段 Tab 中的下标 */
  private sourceIndex(): number {
    for (let i = 0; i < this.sources.length; i++) {
      if (this.sources[i].id === this.currentSourceId) return i;
    }
    return 0;
  }

  /** 文件 Tab 标签数组 */
  private sourceLabels(): string[] {
    const out: string[] = [];
    for (const s of this.sources) {
      out.push(s.label);
    }
    return out;
  }

  // ─── 权限管理 ─────────────────────────────────

  /** 自定义文件选中后的持久化授权（fileShare URI 链）。
   *  内置 ~/.zshrc / ~/.bashrc 不经此——READ_WRITE_USER_FILE ACL 主进程直读直写。 */
  private async persistPermission(uri: string): Promise<boolean> {
    try {
      const p: fileShare.PolicyInfo = { uri: uri, operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE };
      await fileShare.persistPermission([p]);
      return true;
    } catch (e) { return false; }
  }

  /** 入口加载。2026-11-17 真机验证：READ_WRITE_USER_FILE ACL 下主进程可直读直写用户
   *  目录（同进程安装链 DevEnvPaths fs 直写 ~/.zshrc 早已实证）——授权门与
   *  home_uri/fileShare 恢复链移除。原判定把 ENOENT（文件不存在）误判为无权限，
   *  全新机器无 .zshrc 时误弹授权；文件缺失由 markMissing 呈现「已失效」态。 */
  initPermissionAndLoad(): void {
    this.loadAllSources();
  }

  // ─── 文件读写 ─────────────────────────────────

  loadAllSources(): void {
    this.loading = true;
    this.sourceIds = [];
    this.fileLinesArr = [];
    this.displayListArr = [];
    for (const s of this.sources) {
      this.loadSingleSource(s);
    }
    // 重载即重估缺失态（刷新按钮/入口统一走此——同步、保存都可能新建文件，
    // 只在进页重估会出现"点了刷新失效标识也不掉"）
    this.markMissing();
    this.expandedSet = '';
    this.clearModified();
    this.hasUnsaved = false;
    this.applyFilter();
    this.loading = false;
  }

  private loadSingleSource(si: SourceInfo): void {
    const content: string = this.readFileContent(si.path);
    this.setFileLines(si.id, this.parseFileLines(content));
    this.setDisplayList(si.id, this.mergeExportVars(this.getFileLines(si.id)));
  }

  private readFileContent(path: string): string {
    try {
      const stat = fs.statSync(path);
      if (stat.size > 0) {
        const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        fs.closeSync(file.fd);
        return new util.TextDecoder('utf-8').decode(new Uint8Array(buf));
      }
    } catch (e) {
      Logger.info(TAG, `File not found: ${path}`);
    }
    return '';
  }

  private parseFileLines(content: string): FileLine[] {
    const result: FileLine[] = [];
    if (!content || content.length === 0) return result;
    const lines: string[] = content.split('\n');
    // DevBox 托管块跟踪（# >>> ohpcd devenv >>> … # <<< ohpcd devenv <<<；兼容 devbox 旧标记）：
    // 块内行保存时必须原样透传——重写会套单引号使 $PATH/$HOME 不再展开（PATH 损坏——审查 P0-4）
    let inBlock: boolean = false;
    for (let i = 0; i < lines.length; i++) {
      const fl: FileLine = new FileLine();
      fl.text = lines[i];
      fl.lineNum = i;
      const trimmed: string = lines[i].trim();
      if (/^#\s*>>>\s*(ohpcd devenv|devbox)/.test(trimmed)) { inBlock = true; }
      if (inBlock) { fl.inManagedBlock = true; }
      if (/^#\s*<<<\s*(ohpcd devenv|devbox)/.test(trimmed)) {
        result.push(fl);
        inBlock = false;
        continue;
      }
      if (trimmed.startsWith('export ')) {
        const rest: string = trimmed.substring(7).trim();
        const eqIdx: number = rest.indexOf('=');
        if (eqIdx > 0) {
          const name: string = rest.substring(0, eqIdx).trim();
          if (this.isValidVarName(name)) {
            let val: string = rest.substring(eqIdx + 1).trim();
            // 行内注释剥离：第一个"引号外且前置空白"的 #（shell 注释语义；引号内 # 是值一部分
            // 不剥——显示/编辑用干净值，注释独立存 fl.exportComment，保存时拼回不丢）
            let comment: string = '';
            let cut: number = -1;
            let inS: boolean = false;
            let inD: boolean = false;
            for (let ci = 0; ci < val.length; ci++) {
              const ch: string = val.charAt(ci);
              if (ch === "'" && !inD) { inS = !inS; continue; }
              if (ch === '"' && !inS) { inD = !inD; continue; }
              if (!inS && !inD && ch === '#' && ci > 0 && (val.charAt(ci - 1) === ' ' || val.charAt(ci - 1) === '\t')) {
                cut = ci;
                break;
              }
            }
            if (cut >= 0) {
              comment = val.substring(cut).trim();
              val = val.substring(0, cut).trim();
            }
            if ((val.startsWith('"') && val.endsWith('"') && val.length >= 2) ||
              (val.startsWith("'") && val.endsWith("'") && val.length >= 2)) {
              val = val.substring(1, val.length - 1);
            }
            fl.isExport = true;
            fl.exportName = name;
            fl.exportValue = val;
            fl.exportComment = comment;
          }
        }
      }
      result.push(fl);
    }
    return result;
  }

  private resolveSelfRef(value: string, varName: string, existingValue: string): string {
    let result: string = value;
    const braced: string = '${' + varName + '}';
    const simple: string = '$' + varName;
    while (result.includes(braced)) {
      result = result.replace(braced, existingValue);
    }
    let from: number = 0;
    while (from < result.length) {
      const pos: number = result.indexOf(simple, from);
      if (pos < 0) break;
      const after: number = pos + simple.length;
      if (after < result.length) {
        const ch: number = result.charCodeAt(after);
        if ((ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || (ch >= 48 && ch <= 57) || ch === 95) {
          from = after;
          continue;
        }
      }
      result = result.substring(0, pos) + existingValue + result.substring(after);
      from = pos + existingValue.length;
    }
    return result;
  }

  private mergeExportVars(fileLines: FileLine[]): EnvEntry[] {
    const result: EnvEntry[] = [];
    for (const fl of fileLines) {
      if (!fl.isExport) continue;
      let foundIdx: number = -1;
      for (let i = 0; i < result.length; i++) {
        if (result[i].name === fl.exportName) { foundIdx = i; break; }
      }
      if (foundIdx >= 0) {
        const resolved: string = this.resolveSelfRef(fl.exportValue, fl.exportName, result[foundIdx].value);
        result[foundIdx].value += ':' + resolved;
        result[foundIdx].isMulti = result[foundIdx].value.includes(':');
        result[foundIdx].lineNums.push(fl.lineNum);
      } else {
        const e: EnvEntry = new EnvEntry();
        e.name = fl.exportName;
        e.value = fl.exportValue;
        e.isMulti = fl.exportValue.includes(':');
        e.expanded = false;
        e.lineNums = [fl.lineNum];
        e.managed = fl.inManagedBlock;
        result.push(e);
      }
    }
    return result;
  }

  private isValidVarName(name: string): boolean {
    if (name.length === 0) return false;
    const first: number = name.charCodeAt(0);
    if (!((first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first === 95)) return false;
    for (let i = 0; i < name.length; i++) {
      const c: number = name.charCodeAt(i);
      if (!((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c === 95)) return false;
    }
    return true;
  }

  private currentFileLines(): FileLine[] {
    return this.getFileLines(this.currentSourceId);
  }

  private currentDisplayList(): EnvEntry[] {
    return this.getDisplayList(this.currentSourceId);
  }

  // ─── 展开/子项操作 ─────────────────────────────────

  private isExpanded(name: string): boolean {
    if (this.expandedSet.length === 0) return false;
    const parts: string[] = this.expandedSet.split(',');
    for (const p of parts) { if (p === name) return true; }
    return false;
  }

  toggleExpand(name: string): void {
    const current: boolean = this.isExpanded(name);
    if (current) {
      const parts: string[] = this.expandedSet.split(',');
      const np: string[] = [];
      for (const p of parts) { if (p !== name && p.length > 0) np.push(p); }
      this.expandedSet = np.join(',');
    } else {
      this.expandedSet = this.expandedSet.length > 0 ? this.expandedSet + ',' + name : name;
    }
    this.applyFilter();
  }

  private getSubItems(entry: EnvEntry): string[] {
    if (!entry.isMulti) return [];
    const parts: string[] = entry.value.split(':');
    const result: string[] = [];
    for (const p of parts) { const t: string = p.trim(); if (t.length > 0) result.push(t); }
    return result;
  }

  private updateEntryValue(entryName: string, newValue: string): void {
    const list: EnvEntry[] = this.currentDisplayList();
    const newList: EnvEntry[] = [];
    for (const item of list) {
      const e: EnvEntry = new EnvEntry();
      e.name = item.name;
      e.lineNums = item.lineNums;
      if (item.name === entryName) {
        e.value = newValue;
        e.isMulti = newValue.includes(':');
      } else {
        e.value = item.value;
        e.isMulti = item.isMulti;
      }
      e.expanded = item.expanded;
      newList.push(e);
    }
    this.setDisplayList(this.currentSourceId, newList);
    this.hasUnsaved = true;
    this.applyFilter();
  }

  removeSubItem(entryName: string, subIdx: number): void {
    const list: EnvEntry[] = this.currentDisplayList();
    let entry: EnvEntry | null = null;
    for (const item of list) { if (item.name === entryName) { entry = item; break; } }
    if (!entry) return;
    const subs: string[] = this.getSubItems(entry);
    if (subIdx < 0 || subIdx >= subs.length) return;
    const ns: string[] = [];
    for (let i = 0; i < subs.length; i++) { if (i !== subIdx) ns.push(subs[i]); }
    this.updateEntryValue(entryName, ns.join(':'));
    this.markModified(entryName);
  }

  moveSubItem(entryName: string, subIdx: number): void {
    const list: EnvEntry[] = this.currentDisplayList();
    let entry: EnvEntry | null = null;
    for (const item of list) { if (item.name === entryName) { entry = item; break; } }
    if (!entry) return;
    const subs: string[] = this.getSubItems(entry);
    if (subIdx <= 0 || subIdx >= subs.length) return;
    const ns: string[] = [];
    for (let i = 0; i < subs.length; i++) {
      if (i === subIdx - 1) ns.push(subs[subIdx]);
      else if (i === subIdx) ns.push(subs[subIdx - 1]);
      else ns.push(subs[i]);
    }
    this.updateEntryValue(entryName, ns.join(':'));
    this.markModified(entryName);
  }

  moveSubItemDown(entryName: string, subIdx: number): void {
    const list: EnvEntry[] = this.currentDisplayList();
    let entry: EnvEntry | null = null;
    for (const item of list) { if (item.name === entryName) { entry = item; break; } }
    if (!entry) return;
    const subs: string[] = this.getSubItems(entry);
    if (subIdx < 0 || subIdx >= subs.length - 1) return;
    const ns: string[] = [];
    for (let i = 0; i < subs.length; i++) {
      if (i === subIdx) ns.push(subs[subIdx + 1]);
      else if (i === subIdx + 1) ns.push(subs[subIdx]);
      else ns.push(subs[i]);
    }
    this.updateEntryValue(entryName, ns.join(':'));
    this.markModified(entryName);
  }

  editSubItem(entryName: string, subIdx: number, newVal: string): void {
    const list: EnvEntry[] = this.currentDisplayList();
    let entry: EnvEntry | null = null;
    for (const item of list) { if (item.name === entryName) { entry = item; break; } }
    if (!entry) return;
    const subs: string[] = this.getSubItems(entry);
    if (subIdx < 0 || subIdx >= subs.length) return;
    const ns: string[] = [];
    for (let i = 0; i < subs.length; i++) { ns.push(i === subIdx ? newVal.trim() : subs[i]); }
    this.updateEntryValue(entryName, ns.join(':'));
    this.markModified(entryName);
    if (this.editDialogCtrl) { try { this.editDialogCtrl.close(); } catch (e) { } }
  }

  // ─── 过滤/搜索 ─────────────────────────────────

  applyFilter(): void {
    const list: EnvEntry[] = this.currentDisplayList();
    const kw: string = this.searchKeyword ?? '';
    const build = (src: EnvEntry[]): EnvEntry[] => {
      const r: EnvEntry[] = [];
      for (const item of src) {
        const e: EnvEntry = new EnvEntry();
        e.name = item.name; e.value = item.value; e.isMulti = item.isMulti;
        e.expanded = this.isExpanded(item.name); e.lineNums = item.lineNums;
        r.push(e);
      }
      return r;
    };
    if (kw.length === 0) {
      this.filteredList = build(list);
      return;
    }
    const filtered: EnvEntry[] = [];
    for (const item of list) {
      if (item.name.toLowerCase().includes(kw.toLowerCase()) ||
        item.value.toLowerCase().includes(kw.toLowerCase())) {
        const e: EnvEntry = new EnvEntry();
        e.name = item.name; e.value = item.value; e.isMulti = item.isMulti;
        e.expanded = this.isExpanded(item.name); e.lineNums = item.lineNums;
        filtered.push(e);
      }
    }
    this.filteredList = filtered;
  }

  // ─── 保存 ─────────────────────────────────

  /** E2 桩：撤销未保存修改 */
  private revertChanges(): void {
    // 丢弃未保存改动：从磁盘重载当前配置文件
    const si: SourceInfo = this.currentSource();
    this.loadSingleSource(si);
    this.clearModified();
    this.hasUnsaved = false;
    this.applyFilter();
    DevToast.ok($r('app.string.env_manager_2'));
  }

  async saveToFile(): Promise<void> {
    // ⚠ saving 不在此置位（审计：AlertDialog 遮罩关闭不回调 onChoice——
    //   弹窗分支 return 会把 saving 永久卡 true，保存按钮假死到页面重建）
    //   改由 doSaveLines 起止自管；弹窗期间按钮可再点（幂等重弹，无害）
    const si: SourceInfo = this.currentSource();
    Logger.info(TAG, `saveToFile called: ${si.path}`);
    const fileLines: FileLine[] = this.currentFileLines();
    const displayList: EnvEntry[] = this.currentDisplayList();
    const usedLineNums: number[] = [];
    const outputLines: string[] = [];

    for (const fl of fileLines) {
      if (fl.inManagedBlock) {
        // DevBox 托管块原样透传（审查 P0-4）：解析重排/单引号包裹都会破坏块内
        // export PATH=$HOME/...:$PATH 的展开语义（$PATH 被单引号包裹后不展开——PATH 损坏）
        outputLines.push(fl.text);
        continue;
      }
      if (fl.isExport) {
        let found: EnvEntry | null = null;
        for (const d of displayList) { if (d.name === fl.exportName) { found = d; break; } }
        if (!found) continue;
        let already: boolean = false;
        for (const u of usedLineNums) { if (u === fl.lineNum) { already = true; break; } }
        if (already) continue;
        for (const ln of found.lineNums) { usedLineNums.push(ln); }
        const v: string = found.value;
        // POSIX 单引号转义：值内每个 ' 写为 '\''（闭合+转义引号+重开）。
        // ⚠ 源码字面量必须为 "'\\''"（求值 = '\'' 四字符）——写成 "'\''" 求值是
        //   ''' 三个字符（丢反斜杠），良性含引号值即损坏 .zshrc（审计 P0）
        const safeV = v.replace(/'/g, "'\\''");
        // 行尾注释拼回（解析时剥离存 fl.exportComment——保存不能吃掉用户注释）
        outputLines.push(`export ${found.name}='${safeV}'${fl.exportComment !== '' ? ' ' + fl.exportComment : ''}`);
      } else {
        outputLines.push(fl.text);
      }
    }
    for (const d of displayList) {
      if (d.lineNums.length === 0) {
        const v: string = d.value;
        outputLines.push((v.includes(' ') || v.includes('$') || v.includes(':')) ?
          `export ${d.name}="${v}"` : `export ${d.name}=${v}`);
        continue;
      }
      // 托管条目编辑落用户行（brew PATH 优先功能配套修复）：条目所有行都在托管块
      // （如 PATH——块行只读透传）且值被修改过 → 此前修改被静默丢弃（无写点）。
      // 现在追加为块后用户行（与"新增"同语义）：用户 PATH 覆盖按 shell 顺序语义
      // 生效；brew 优先开着时由保存前冲突弹窗裁决（DevEnvPaths.brewPriorityConflict）。
      // ⚠ 引号策略（审计 4a，中危·文件破坏）：恒单引号会冻结 $HOME/$PATH 引用
      //   → 用户 shell PATH 全损（同文件 P0-4 沉淀的教训）——含 $ 一律双引号保展开
      //   （$(…) 命令替换风险属用户主权内容，与新增/doSync 同策略）
      if (this.isModified(d.name) && !this.hasWritableLine(d, fileLines)) {
        const v: string = d.value;
        if (v.includes('$')) {
          outputLines.push(`export ${d.name}="${v}"`);
        } else {
          outputLines.push(`export ${d.name}='${v.replace(/'/g, "'\\''")}'`);
        }
      }
    }

    // ── brew PATH 优先冲突检测（勾选项开着 + 托管块后出现前置式用户 PATH 行）──
    // 前置行在 shell 顺序语义上压制块内 .harmonybrew 段——弹窗让用户裁决：
    // 调整（行移到块前，块重写后必再后置=brew 恢复最前）/ 保留（按用户原样保存）
    const conflictIdx: number = DevEnvPaths.brewPriorityConflict(outputLines);
    if (conflictIdx >= 0) {
      const preview: string = outputLines[conflictIdx].trim().slice(0, 70);
      DevConfirm.choice(
        'brew PATH 优先受影响',
        `检测到 DevBox 托管块之后有 PATH 前置行：\n${preview}\n\n该行会让其中的目录优先于 brew 安装的软件。`,
        [
          { text: '调整（brew 优先）' },
          { text: '保留我的修改' },
        ],
        (idx: number) => {
          if (idx < 0) {
            // 关闭弹窗 = 放弃本次保存（未保存标记保留）
            DevToast.show($r('app.string.env_manager_3'));
            return;
          }
          const finalLines: string[] = idx === 0
            ? DevEnvPaths.resolveBrewPriorityConflict(outputLines)
            : outputLines;
          this.doSaveLines(finalLines, si);
        },
      );
      return;
    }
    this.doSaveLines(outputLines, si);
  }

  /** 条目是否存在非托管的可写行（托管块行只读透传——写它会破坏 $PATH/$HOME 展开语义） */
  private hasWritableLine(d: EnvEntry, fileLines: FileLine[]): boolean {
    for (const ln of d.lineNums) {
      for (const fl of fileLines) {
        if (fl.lineNum === ln) {
          if (!fl.inManagedBlock && fl.isExport) {
            return true;
          }
          break;
        }
      }
    }
    return false;
  }

  /** 实际落盘（saveToFile 尾部抽取——冲突弹窗两分支复用） */
  /** 实际落盘（saveToFile 尾部抽取——冲突弹窗两分支复用；saving 起止自管） */
  private doSaveLines(lines: string[], si: SourceInfo): void {
    this.saving = true;
    const outputLines = lines;
    try {
      const file = fs.openSync(si.path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, outputLines.join('\n'));
      fs.closeSync(file.fd);
      this.hasUnsaved = false;
      this.clearModified();
      this.loadSingleSource(si);
      this.applyFilter();
      // 保存可能新建文件（原「已失效」态）——重估 missing，卡片即时摘掉失效标识
      // （markMissing 只在进页/刷新时跑，保存后不重估=失效标识残留，用户实测发现）
      this.markMissing();
      // 卡片计数是 ForEach 内的非状态读取，saving 未被 build 读取翻转无效——重赋 sources 强制重算
      this.sources = [...this.sources];
      DevToast.ok(`已保存 ${outputLines.length} 行到 ${si.label}`);
      Logger.info(TAG, `saveToFile OK: ${outputLines.length} lines -> ${si.path}`);
    } catch (e) {
      DevToast.show(`保存失败：${JSON.stringify(e)}`.slice(0, 80));
      Logger.error(TAG, `Save failed: ${JSON.stringify(e)}`);
    }
    this.saving = false;
  }

  switchSource(id: string): void {
    if (this.currentSourceId === id) return;
    this.currentSourceId = id;
    this.searchKeyword = '';
    this.expandedSet = '';
    this.clearModified();
    this.hasUnsaved = false;
    this.applyFilter();
  }

  private openEditDialog(entryName: string, entryValue: string): void {
    this.isAddMode = false; this.editOrigName = entryName;
    this.editDialogCtrl = new CustomDialogController({
      builder: EditDialogBuilder({
        isAddMode: false, editName: entryName, editValue: entryValue,
        existingNames: this.getExistingNames(),
        onConfirm: (n: string, v: string) => this.confirmEdit(n, v),
        onCancel: () => { if (this.editDialogCtrl) { try { this.editDialogCtrl.close(); } catch (e) { } } },
      }),
      alignment: DialogAlignment.Center, autoCancel: true, customStyle: true, maskColor: DevTheme.BG_OVERLAY,
    });
    this.editDialogCtrl.open();
  }

  private openSubItemEditDialog(entryName: string, subIdx: number, subVal: string): void {
    this.editOrigName = entryName;
    this.editDialogCtrl = new CustomDialogController({
      builder: EditDialogBuilder({
        isAddMode: false, editName: '', editValue: subVal, existingNames: '',
        onConfirm: (_n: string, v: string) => this.editSubItem(entryName, subIdx, v),
        onCancel: () => { if (this.editDialogCtrl) { try { this.editDialogCtrl.close(); } catch (e) { } } },
      }),
      alignment: DialogAlignment.Center, autoCancel: true, customStyle: true, maskColor: DevTheme.BG_OVERLAY,
    });
    this.editDialogCtrl.open();
  }

  confirmEdit(name: string, value: string): void {
    name = name.trim(); value = value.trim();
    const list: EnvEntry[] = this.currentDisplayList();
    if (this.isAddMode) {
      const e: EnvEntry = new EnvEntry();
      e.name = name; e.value = value; e.isMulti = value.includes(':');
      e.expanded = false; e.lineNums = [];
      list.push(e);
      this.markAdded(name);
    } else {
      for (const item of list) {
        if (item.name === this.editOrigName) {
          item.name = name; item.value = value; item.isMulti = value.includes(':');
          break;
        }
      }
      this.markModified(name);
    }
    this.setDisplayList(this.currentSourceId, [...list]);
    this.hasUnsaved = true;
    this.applyFilter();
    if (this.editDialogCtrl) { try { this.editDialogCtrl.close(); } catch (e) { } }
  }

  confirmDelete(): void {
    const name: string = this.deleteTargetName;
    const list: EnvEntry[] = this.currentDisplayList();
    const nl: EnvEntry[] = [];
    for (const item of list) { if (item.name !== name) nl.push(item); }
    this.setDisplayList(this.currentSourceId, [...nl]);
    this.hasUnsaved = true;
    this.applyFilter();
    if (this.deleteDialogCtrl) { try { this.deleteDialogCtrl.close(); } catch (e) { } }
  }

  // ─── 同步 ─────────────────────────────────

  private sourceById(id: string): SourceInfo | null {
    for (const s of this.sources) {
      if (s.id === id) return s;
    }
    return null;
  }

  /** 同步：把源文件变量追加写入目标文件（同名跳过），直接落盘并重载内存 */
  async doSync(): Promise<void> {
    if (this.syncFromId.length === 0 || this.syncTargetIds.length === 0) return;
    const fromSi: SourceInfo | null = this.sourceById(this.syncFromId);
    if (fromSi === null) return;
    const fromList: EnvEntry[] = this.getDisplayList(this.syncFromId);
    const targetIds: string[] = this.syncTargetIds.split(',');
    let totalAdded: number = 0;
    let lastTarget: string = '';

    for (const tid of targetIds) {
      if (tid.length === 0 || tid === this.syncFromId) continue;
      const tSi: SourceInfo | null = this.sourceById(tid);
      if (tSi === null) continue;
      const existing: EnvEntry[] = this.getDisplayList(tid);
      // 目标缺失的变量 → 追加 export 行
      const appendLines: string[] = [];
      for (const src of fromList) {
        let found: boolean = false;
        for (const t of existing) {
          if (t.name === src.name) { found = true; break; }
        }
        if (found) continue;
        const v: string = src.value;
        appendLines.push((v.includes(' ') || v.includes('$') || v.includes(':')) ?
          `export ${src.name}="${v}"` : `export ${src.name}=${v}`);
      }
      if (appendLines.length === 0) continue;

      // 读原文件 → 末尾追加 → 落盘
      let out: string = this.readFileContent(tSi.path);
      if (out.length > 0 && !out.endsWith('\n')) { out += '\n'; }
      out += appendLines.join('\n') + '\n';
      try {
        const file = fs.openSync(tSi.path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(file.fd, out);
        fs.closeSync(file.fd);
        this.loadSingleSource(tSi);
        totalAdded += appendLines.length;
        lastTarget = tSi.label;
      } catch (e) {
        DevToast.show(`同步失败：${tSi.label}`);
        Logger.error(TAG, `sync write failed: ${JSON.stringify(e)}`);
        return;
      }
    }
    this.applyFilter();
    // 同步可能新建目标文件（原「已失效」态）——重估 missing，卡片即时摘掉失效标识
    this.markMissing();
    // 卡片计数是 ForEach 内的非状态读取，须重赋 sources 触发 key 重算（count 才会刷新）
    this.sources = [...this.sources];
    DevToast.ok(totalAdded > 0
      ? `已同步 ${totalAdded} 个变量到 ${lastTarget}`
      : '目标文件已包含全部变量，无需同步');
  }

  // ─── 辅助 ─────────────────────────────────

  private getExistingNames(): string {
    let r: string = '';
    for (const e of this.currentDisplayList()) { if (r.length > 0) r += ','; r += e.name; }
    return r;
  }

  // ─── UI ─────────────────────────────────

  build() {
    Column() {
      DevPageHeader({
        title: '环境变量',
        subtitle: '管理 shell 配置文件中的环境变量',
        showDivider: false,
      })
        .margin({ bottom: 12 })

      if (this.loading) {
        Column() {
          LoadingProgress().width(32).height(32).color(DevTheme.PRIMARY)
          Text($r('app.string.env_manager_4')).fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_MUTED).margin({ top: 8 })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        this.buildMainContent()
      }
    }
    .width('100%').height('100%')
    .padding({ left: 24, right: 24, top: 8, bottom: 16 })
  }

  @Builder
  buildMainContent() {
    Scroll() {
      Column({ space: 10 }) {
        // ── 顶部操作行 ──
        Row({ space: 8 }) {
          DevBtn({ text: '刷新', buttonSize: 'mini', plain: true,
            onTap: () => this.loadAllSources() })
          DevBtn({
            text: '同步', buttonSize: 'mini', plain: true,
            onTap: () => { this.openSyncDialog(); },
          })
          DevBtn({
            text: '添加', buttonSize: 'mini', plain: true,
            onTap: () => { this.openAddFileDialog(); },
          })
          Blank()
          Text(`${this.sources.length} 个配置文件`)
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
        }.width('100%')

        // ── 配置文件卡片列表 ──
        ForEach(this.sources, (s: SourceInfo) => {
          this.buildFileCard(s)
        }, (s: SourceInfo) => `${s.id}_${s.missing}_${this.expandedFile === s.id}_${this.getDisplayList(s.id).length}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .align(Alignment.TopStart)
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  /** 单个配置文件卡片（收起态=概要；展开态=变量表格） */
  @Builder
  buildFileCard(s: SourceInfo) {
    DevCard({ title: '', subtitle: '', accent: '', pad: 14 }) {
      Column({ space: 10 }) {
        Row({ space: 12 }) {
          Column({ space: 3 }) {
            Row({ space: 6 }) {
              Text(s.label).fontSize(DevTheme.FS_H3).fontWeight(FontWeight.Medium)
                .fontFamily(DevTheme.MONO_FONT)
                .fontColor(s.missing ? DevTheme.TEXT_TERTIARY : DevTheme.TEXT_PRIMARY)
              if (s.missing) {
                Text($r('app.string.env_manager_5')).fontSize(DevTheme.FS_CAPTION)
                  .fontColor(DevTheme.DANGER)
                  .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                  .borderRadius(4)
                  .border({ width: 1, color: DevTheme.DANGER })
              }
            }.alignItems(VerticalAlign.Center)
            Text(s.missing
              ? '文件不存在 · 新增变量保存后自动创建（也可能被其他应用删除）'
              : `${this.descOf(s)} · ${this.getDisplayList(s.id).length} 个 export`)
              .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          DevBtn({
            text: this.expandedFile === s.id ? '收起' : '详细',
            buttonSize: 'mini', plain: true,
            onTap: () => { this.toggleFile(s.id); },
          })
        }.width('100%')

        // ── 展开态：变量表格 + 操作 ──
        if (this.expandedFile === s.id) {
          this.buildVarTable()
        }
      }.width('100%')
    }
  }

  private descOf(s: SourceInfo): string {
    if (s.id === 'zshrc') { return 'zsh 解释器环境变量（默认 Shell）'; }
    if (s.id === 'bashrc') { return 'bash 解释器环境变量'; }
    return s.path;
  }

  private toggleFile(id: string): void {
    if (this.expandedFile === id) {
      this.expandedFile = '';
      return;
    }
    this.switchSource(id);
    this.expandedFile = id;
    this.selectedVar = '';
  }

  /** 变量表格（搜索 + 表头 + 行选择 + 底部操作；作用于当前展开文件） */
  @Builder
  buildVarTable() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        DevInput({
          value: this.searchKeyword,
          placeholder: '搜索变量名或值…', mono: false,
          onChange: (v: string) => { this.searchKeyword = v; this.applyFilter(); },
        })
        if (this.hasUnsaved) {
          DevChip({ text: '未保存', tone: 'danger', mono: false })
        } else if (this.getModifiedCount() > 0) {
          DevChip({ text: `${this.getModifiedCount()} 个已修改`, tone: 'warning', mono: false })
        }
      }.width('100%')

      Column() {
        Row({ space: 8 }) {
          Text($r('app.string.env_manager_6')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
            .width(160).textAlign(TextAlign.Start)
          Text($r('app.string.env_manager_7')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
            .layoutWeight(1).textAlign(TextAlign.Start)
        }.width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .border({ width: { bottom: 1 }, color: DevTheme.BORDER })

        if (this.filteredList.length === 0) {
          Text(this.searchKeyword.length > 0 ? '没有匹配的变量' : '暂无环境变量')
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY).padding(16)
        } else {
          Scroll() {
            Column() {
              ForEach(this.filteredList, (item: EnvEntry) => {
                Row({ space: 8 }) {
                  Text(item.name).fontSize(DevTheme.FS_BODY).fontFamily(DevTheme.MONO_FONT)
                    .fontColor(DevTheme.TEXT_PRIMARY).width(160)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.value).fontSize(DevTheme.FS_BODY).fontFamily(DevTheme.MONO_FONT)
                    .fontColor(DevTheme.TEXT_SECONDARY).layoutWeight(1)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.isNew(item.name)) {
                    DevChip({ text: '新增', tone: 'success', mono: false })
                  } else if (this.isModified(item.name)) {
                    // 审计 C-P0-1：此前有连续两个相同 else-if，第一个空体
                    // 吞掉命中——"已修改"徽标永不渲染。删空分支。
                    DevChip({ text: '已修改', tone: 'warning', mono: false })
                  }
                }.width('100%')
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(DevTheme.RADIUS_SM)
                .backgroundColor(this.selectedVar === item.name ? DevTheme.BG_ACCENT_PRIMARY : Color.Transparent)
                .onClick(() => {
                  this.selectedVar = this.selectedVar === item.name ? '' : item.name;
                })
                .gesture(
                  TapGesture({ count: 2 })
                    .onAction(() => {
                      this.selectedVar = item.name;
                      this.openEditDialog(item.name, item.value);
                    })
                )
              }, (item: EnvEntry) => `${item.name}_${item.value}_${this.selectedVar === item.name}_${this.isNew(item.name)}_${this.isModified(item.name)}`)
            }.width('100%')
          }
          .width('100%')
          .constraintSize({ maxHeight: 340 })
          .scrollBar(BarState.Auto)
        }
      }.width('100%')
      .borderRadius(DevTheme.RADIUS_SM)
      .border({ width: 1, color: DevTheme.BORDER })

      Row({ space: 8 }) {
        if (!this.currentSource().isBuiltIn) {
          DevBtn({
            text: '移除此文件', buttonSize: 'mini', plain: true,
            onTap: () => { this.askRemoveFile(); },
          })
        }
        Blank()
        DevBtn({
          text: '新增', buttonSize: 'mini',
          onTap: () => { this.openAddVarDialog(); },
        })
        DevBtn({
          text: '编辑', buttonSize: 'mini', plain: true,
          onTap: () => {
            const item: EnvEntry | undefined = this.findEntry(this.selectedVar);
            if (item === undefined) { DevToast.show($r('app.string.env_manager_8')); return; }
            this.openEditDialog(item.name, item.value);
          },
        })
        DevBtn({
          text: '删除', buttonSize: 'mini', plain: true, danger: true,
          onTap: () => {
            if (this.selectedVar === '') { DevToast.show($r('app.string.env_manager_8')); return; }
            this.deleteTargetName = this.selectedVar;
            DevConfirm.danger(
              `删除变量 ${this.selectedVar}`,
              '删除后点击「保存」才会写入配置文件，在此之前可随时还原。',
              () => { this.confirmDelete(); this.selectedVar = ''; },
              '删除',
            );
          },
        })
        if (this.hasUnsaved || this.getModifiedCount() > 0) {
          DevBtn({
            text: this.saving ? '保存中…' : '保存', buttonSize: 'mini', loading: this.saving,
            onTap: () => { this.saveToFile(); },
          })
          DevBtn({ text: '撤销', buttonSize: 'mini', plain: true, onTap: () => { this.revertChanges(); } })
        }
      }.width('100%')
    }.width('100%')
  }

  private findEntry(name: string): EnvEntry | undefined {
    for (const e of this.filteredList) {
      if (e.name === name) { return e; }
    }
    return undefined;
  }

  private openSyncDialog(): void {
    this.syncFromId = this.currentSourceId;
    this.syncTargetIds = '';
    this.syncDialogCtrl = new CustomDialogController({
      builder: SyncDialogBuilder({
        sources: this.sources,
        currentId: this.currentSourceId,
                onConfirm: (sourceId: string, targetId: string) => {
          this.syncFromId = sourceId;
          this.syncTargetIds = targetId;
          // 先关弹窗再执行（CustomDialog 回调中直接做 UI/文件操作会崩溃）
          if (this.syncDialogCtrl) {
            try { this.syncDialogCtrl.close(); } catch (e) {
            }
          }
          setTimeout(() => { this.doSync(); }, 200);
        },
        onCancel: () => {
          if (this.syncDialogCtrl) {
            try { this.syncDialogCtrl.close(); } catch (e) {
            }
          }
        },
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      customStyle: true,
      maskColor: DevTheme.BG_OVERLAY,
    });
    this.syncDialogCtrl.open();
  }

  private openAddFileDialog(): void {
    this.addFileDialogCtrl = new CustomDialogController({
      builder: AddFileDialogBuilder({
        onConfirm: (label: string, path: string, uri: string) => {
          this.addCustomSource(label, path);
          // 浏览器选中的文件持久化授权（重启后按路径仍可读写）
          if (uri.startsWith('file://')) {
            this.persistPermission(uri);
          }
          if (this.addFileDialogCtrl) {
            try { this.addFileDialogCtrl.close(); } catch (e) {
            }
          }
        },
        onCancel: () => {
          if (this.addFileDialogCtrl) {
            try { this.addFileDialogCtrl.close(); } catch (e) {
            }
          }
        },
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      customStyle: true,
      maskColor: DevTheme.BG_OVERLAY,
    });
    this.addFileDialogCtrl.open();
  }

  private openAddVarDialog(): void {
    this.isAddMode = true;
    this.editOrigName = '';
    this.editDialogCtrl = new CustomDialogController({
      builder: EditDialogBuilder({
        isAddMode: true, editName: '', editValue: '', existingNames: this.getExistingNames(),
        onConfirm: (n: string, v: string) => this.confirmEdit(n, v),
        onCancel: () => {
          if (this.editDialogCtrl) {
            try { this.editDialogCtrl.close(); } catch (e) {
            }
          }
        },
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      customStyle: true,
      maskColor: DevTheme.BG_OVERLAY,
    });
    this.editDialogCtrl.open();
  }
}

// ─── 编辑弹窗 ──────────────────────────

@CustomDialog
struct EditDialogBuilder {
  controller: CustomDialogController;
  @Prop isAddMode: boolean = true;
  @Prop editName: string = '';
  @Prop editValue: string = '';
  @Prop existingNames: string = '';
  onConfirm: (name: string, value: string) => void = (_n: string, _v: string) => {};
  onCancel: () => void = () => {};
  @State localName: string = '';
  @State localValues: string[] = [];
  @State localError: string = '';
  @State pressedKey: string = '';  // 行内按钮按下态（格式 'idx_↑'）
  @State swapVersion: number = 0;  // 交换计数器（触发 ForEach 重渲染）
  @State dragFrom: number = -1;

  aboutToAppear(): void {
    this.localName = this.editName;
    const raw: string = this.editValue.trim();
    if (raw === '') {
      this.localValues = [''];
    } else {
      this.localValues = raw.split(':');
    }
  }

  private isValidVarName(name: string): boolean {
    if (name.length === 0) return false;
    const first: number = name.charCodeAt(0);
    if (!((first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first === 95)) return false;
    for (let i = 0; i < name.length; i++) {
      const c: number = name.charCodeAt(i);
      if (!((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c === 95)) return false;
    }
    return true;
  }

  /** 从剪贴板读取文本追加为新值行（READ_PASTEBOARD 正式消费点：
   *  复制配置片段/路径后一键粘贴成变量值，免去手动中转） */
  pasteFromClipboard(): void {
    try {
      pasteboard.getSystemPasteboard().getData().then((data: pasteboard.PasteData) => {
        const text: string = data.getPrimaryText();
        if (text === '') {
          DevToast.show($r('app.string.env_manager_9'));
          return;
        }
        // 多行/多值（换行或冒号分隔）拆成多行粘贴
        const parts: string[] = text.split('\n').flatMap((line: string): string[] => line.split(':')).map((x: string): string => x.trim()).filter((x: string): boolean => x !== '');
        if (parts.length === 0) {
          DevToast.show($r('app.string.env_manager_10'));
          return;
        }
        const arr: string[] = this.localValues.slice();
        for (const p of parts) {
          if (arr.length === 1 && arr[0] === '') { arr[0] = p; }
          else { arr.push(p); }
        }
        this.localValues = arr;
        DevToast.ok(`已粘贴 ${parts.length} 个值`);
      }).catch((_e: object) => {
        DevToast.show($r('app.string.env_manager_11'));
      });
    } catch (_) {
      DevToast.show($r('app.string.env_manager_11'));
    }
  }

  private moveUp(idx: number): void {
    if (idx <= 0) { return; }
    const arr: string[] = this.localValues.slice();
    const t: string = arr[idx - 1];
    arr[idx - 1] = arr[idx];
    arr[idx] = t;
    this.localValues = arr;
    this.swapVersion++;  // 触发 ForEach 重渲染（key 含 swapVersion）
  }

  private moveDown(idx: number): void {
    if (idx >= this.localValues.length - 1) { return; }
    const arr: string[] = this.localValues.slice();
    const t: string = arr[idx + 1];
    arr[idx + 1] = arr[idx];
    arr[idx] = t;
    this.localValues = arr;
    this.swapVersion++;
  }

  private removeAt(idx: number): void {
    const arr: string[] = this.localValues.slice();
    arr.splice(idx, 1);
    this.localValues = arr.length > 0 ? arr : [''];
    this.swapVersion++;
  }

  private addRow(): void {
    const arr: string[] = this.localValues.slice();
    arr.push('');
    this.localValues = arr;
  }

  /** 拖拽换位（List onDrop） */
  private dropTo(to: number): void {
    if (this.dragFrom < 0 || this.dragFrom === to) { this.dragFrom = -1; return; }
    const arr: string[] = this.localValues.slice();
    const item: string = arr.splice(this.dragFrom, 1)[0];
    arr.splice(to > this.dragFrom ? to - 1 : to, 0, item);
    this.localValues = arr;
    this.dragFrom = -1;
  }

  private tryConfirm(): void {
    const name: string = this.localName.trim();
    if (name.length === 0) { this.localError = '变量名不能为空'; return; }
    if (!this.isValidVarName(name)) { this.localError = '变量名格式不合法（字母数字下划线）'; return; }
    if (this.isAddMode) {
      const arr: string[] = this.existingNames.split(',');
      for (const n of arr) { if (n === name) { this.localError = '变量名已存在'; return; } }
    }
    const vals: string[] = [];
    for (let i = 0; i < this.localValues.length; i++) {
      const v: string = this.localValues[i].trim();
      if (v !== '') { vals.push(v); }
    }
    if (vals.length === 0) { this.localError = '至少填写一个值'; return; }
    this.localError = '';
    this.onConfirm(name, vals.join(':'));
  }

  build() {
    DevDialogPanel({
      title: this.isAddMode ? '新增环境变量' : `编辑 ${this.editName}`,
      dialogWidth: 520,
      paddingValueLeft: 16,
      paddingValueRight: 16,
      paddingValueTop: 12,
      paddingValueBottom: 16,
    }) {
      Column({ space: 10 }) {
        // ── 变量名 ──
        DevInput({
          value: this.localName,
          placeholder: '变量名（如：JAVA_HOME）',
          mono: true,
          onChange: (v: string) => {
            this.localName = v;
            this.localError = '';
          },
        })
        if (this.localError.length > 0) {
          Text(this.localError).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.DANGER)
        }

        // ── 值列表（每行行内 ↑↓✕，同 Python 镜像管理） ──
        Column({ space: 0 }) {
          List({ space: 0, initialIndex: 0 }) {
            ForEach(this.localValues, (v: string, idx: number) => {
              ListItem() {
                Row({ space: 4 }) {
                  Text(`${idx + 1}`)
                    .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
                    .width(16).textAlign(TextAlign.Center)
                  TextInput({ text: v, placeholder: '输入值' })
                    .fontSize(DevTheme.FS_BODY)
                    .fontFamily(DevTheme.MONO_FONT)
                    .fontColor(DevTheme.TEXT_PRIMARY)
                    .backgroundColor(Color.Transparent)
                    .border({ width: 0 })
                    .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                    .layoutWeight(1)
                    .onChange((nv: string) => {
                      const arr: string[] = this.localValues.slice();
                      arr[idx] = nv;
                      this.localValues = arr;
                    })
                  // 行内按钮（第一行无↑，最后一行无↓）
                  if (idx > 0) {
                    Text('↑').fontSize(DevTheme.FS_H2).fontColor(DevTheme.TEXT_TERTIARY)
                      .width(24).height(24).textAlign(TextAlign.Center)
                      .borderRadius(4)
                      .backgroundColor(this.pressedKey === `${idx}_↑` ? DevTheme.BG_HOVER : Color.Transparent)
                      .scale({ x: this.pressedKey === `${idx}_↑` ? 0.85 : 1, y: this.pressedKey === `${idx}_↑` ? 0.85 : 1 })
                      .animation({ duration: 100, curve: Curve.EaseOut })
                      .onTouch((e: TouchEvent) => {
                        this.pressedKey = e.type === TouchType.Down ? `${idx}_↑` : '';
                      })
                      .onClick(() => { this.moveUp(idx); })
                  }
                  if (idx < this.localValues.length - 1) {
                    Text('↓').fontSize(DevTheme.FS_H2).fontColor(DevTheme.TEXT_TERTIARY)
                      .width(24).height(24).textAlign(TextAlign.Center)
                      .borderRadius(4)
                      .backgroundColor(this.pressedKey === `${idx}_↓` ? DevTheme.BG_HOVER : Color.Transparent)
                      .scale({ x: this.pressedKey === `${idx}_↓` ? 0.85 : 1, y: this.pressedKey === `${idx}_↓` ? 0.85 : 1 })
                      .animation({ duration: 100, curve: Curve.EaseOut })
                      .onTouch((e: TouchEvent) => {
                        this.pressedKey = e.type === TouchType.Down ? `${idx}_↓` : '';
                      })
                      .onClick(() => { this.moveDown(idx); })
                  }
                  Text('✕').fontSize(DevTheme.FS_H2).fontColor(DevTheme.DANGER)
                    .width(24).height(24).textAlign(TextAlign.Center)
                    .borderRadius(4)
                    .backgroundColor(this.pressedKey === `${idx}_✕` ? DevTheme.BG_HOVER : Color.Transparent)
                    .scale({ x: this.pressedKey === `${idx}_✕` ? 0.85 : 1, y: this.pressedKey === `${idx}_✕` ? 0.85 : 1 })
                    .animation({ duration: 100, curve: Curve.EaseOut })
                    .onTouch((e: TouchEvent) => {
                      this.pressedKey = e.type === TouchType.Down ? `${idx}_✕` : '';
                    })
                    .onClick(() => { this.removeAt(idx); })
                }.width('100%').padding({ left: 4, right: 4, top: 2, bottom: 2 })
              }
              .onDragStart(() => {
                this.dragFrom = idx;
                return undefined;
              })
            }, (v: string, idx: number) => `${idx}_${this.swapVersion}`)
          }
          .width('100%')
          .constraintSize({ maxHeight: 260 })
          .scrollBar(BarState.Auto)
          .onDrop(() => this.dropTo(this.localValues.length))
          .divider({ strokeWidth: 0.5, color: DevTheme.BORDER, startMargin: 20, endMargin: 4 })
        }
        .width('100%')
        .borderRadius(DevTheme.RADIUS_MD)
        .backgroundColor(DevTheme.BG_MUTED)
        .border({ width: 1, color: DevTheme.BORDER })

        // 添加值 / 从剪贴板粘贴
        Row({ space: 8 }) {
          Text($r('app.string.env_manager_12'))
            .fontSize(DevTheme.FS_H3).fontColor(DevTheme.TEXT_TERTIARY)
            .layoutWeight(1).textAlign(TextAlign.Center)
            .padding({ top: 6, bottom: 6 })
            .borderRadius(DevTheme.RADIUS_SM)
            .backgroundColor(DevTheme.BG_HOVER)
            .onClick(() => { this.addRow(); })
          Text($r('app.string.env_manager_13'))
            .fontSize(DevTheme.FS_H3).fontColor(DevTheme.TEXT_TERTIARY)
            .layoutWeight(1).textAlign(TextAlign.Center)
            .padding({ top: 6, bottom: 6 })
            .borderRadius(DevTheme.RADIUS_SM)
            .backgroundColor(DevTheme.BG_HOVER)
            .onClick(() => { this.pasteFromClipboard(); })
        }.width('100%')

        // 底部按钮
        Row({ space: 12 }) {
          Blank()
          DevBtn({ text: '取消', buttonSize: 'small', plain: true,
            onTap: () => { this.onCancel(); } })
          DevBtn({ text: this.isAddMode ? '添加' : '保存', buttonSize: 'small',
            onTap: () => { this.tryConfirm(); } })
        }.width('100%').margin({ top: 4 })
      }.width('100%')
    }
  }

}

@CustomDialog
struct SyncDialogBuilder {
  controller: CustomDialogController;
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop sources: SourceInfo[] = [];
  @Prop currentId: string = '';
  onConfirm: (sourceId: string, targetId: string) => void = (_s, _t) => {};
  onCancel: () => void = () => {};
  @State srcIdx: number = 0;
  @State tgtIdx: number = 1;

  aboutToAppear(): void {
    let ci = -1;
    for (let i = 0; i < this.sources.length; i++) {
      if (this.sources[i].id === this.currentId) { ci = i; break; }
    }
    if (ci < 0) { ci = 0; }
    let ti = -1;
    for (let i = 0; i < this.sources.length; i++) {
      if (i !== ci) { ti = i; break; }
    }
    this.srcIdx = ci;
    this.tgtIdx = ti < 0 ? ci : ti;
  }

  /** 滚轮标签：纯文件名（原"（当前）/（编辑中）"标记都删——用户可能根本没编辑过，
   *  任何标记都暗示与 shell 生效/编辑状态有关的误导，语义诚实就是不加） */
  private labels(): string[] {
    return this.sources.map((s: SourceInfo): string => {
      return s.label.replace('~/.', '');
    });
  }

  private sameFile(): boolean {
    const a = this.sources[this.srcIdx];
    const b = this.sources[this.tgtIdx];
    return a !== undefined && b !== undefined && a.id === b.id;
  }

  private srcPath(): string {
    return this.sources[this.srcIdx]?.path ?? '—';
  }

  private tgtPath(): string {
    return this.sources[this.tgtIdx]?.path ?? '—';
  }

  /** 滚轮待选项（邻档）文字样式 */
  private normalStyle(): PickerTextStyle {
    return { color: DevTheme.TEXT_SECONDARY, font: { size: 13, weight: FontWeight.Regular } };
  }

  /** 滚轮边缘项（渐隐档）文字样式 */
  private fadeStyle(): PickerTextStyle {
    return { color: DevTheme.TEXT_MUTED, font: { size: 12, weight: FontWeight.Regular } };
  }

  /** 滚轮选中项文字样式 */
  private pickedStyle(): PickerTextStyle {
    return { color: DevTheme.PRIMARY, font: { size: 15, weight: FontWeight.Medium } };
  }

  build() {
    DevDialogPanel({
      title: '同步环境变量',
      dialogWidth: 420,
      dialogHeight: 364,
      paddingValueLeft: 14,
      paddingValueRight: 14,
      paddingValueTop: 10,
      paddingValueBottom: 14,
    }) {
      Column({ space: 8 }) {
        // ── 列头：源 → 目标 ──
        Row() {
          Text($r('app.string.env_manager_14'))
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
            .layoutWeight(1).textAlign(TextAlign.Center)
          Column().width(28)
          Text($r('app.string.env_manager_15'))
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
            .layoutWeight(1).textAlign(TextAlign.Center)
        }.width('100%')

        // ── 双滚轮：系统 TextPicker（原生物理效果，chrome 自动跟随应用深浅色） ──
        Row() {
          TextPicker({ range: this.labels(), selected: this.srcIdx })
            .canLoop(false)
            .defaultPickerItemHeight(36)
            .textStyle(this.normalStyle())
            .disappearTextStyle(this.fadeStyle())
            .selectedTextStyle(this.pickedStyle())
            .divider({ strokeWidth: 0.5, color: DevTheme.BORDER, startMargin: 6, endMargin: 6 })
            .gradientHeight(22)
            .height(172)
            .layoutWeight(1)
            .onChange((_v: string | string[], index: number | number[]) => {
              this.srcIdx = index as number;
            })

          // 方向指示：同文件时变红
          Column() {
            Text('→')
              .fontSize(DevTheme.FS_H2)
              .fontColor(this.sameFile() ? DevTheme.DANGER : DevTheme.PRIMARY)
              .fontWeight(FontWeight.Bold)
          }
          .width(28)
          .height(172)
          .justifyContent(FlexAlign.Center)

          TextPicker({ range: this.labels(), selected: this.tgtIdx })
            .canLoop(false)
            .defaultPickerItemHeight(36)
            .textStyle(this.normalStyle())
            .disappearTextStyle(this.fadeStyle())
            .selectedTextStyle(this.pickedStyle())
            .divider({ strokeWidth: 0.5, color: DevTheme.BORDER, startMargin: 6, endMargin: 6 })
            .gradientHeight(22)
            .height(172)
            .layoutWeight(1)
            .onChange((_v: string | string[], index: number | number[]) => {
              this.tgtIdx = index as number;
            })
        }.width('100%')

        // ── 同步路径摘要 ──
        Text(`${this.srcPath()}  →  ${this.tgtPath()}`)
          .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
          .width('100%').textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // ── 状态行（常驻，高度恒定）：同文件=红警告 / 正常=合并策略提示 ──
        if (this.sameFile()) {
          Text($r('app.string.env_manager_16'))
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.DANGER)
            .width('100%').textAlign(TextAlign.Center)
        } else {
          Text($r('app.string.env_manager_17'))
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
            .width('100%').textAlign(TextAlign.Center)
        }

        // ── 按钮 ──
        Row({ space: 12 }) {
          Blank()
          DevBtn({ text: '取消', buttonSize: 'small', plain: true,
            onTap: () => { this.onCancel(); } })
          DevBtn({
            text: '开始同步', buttonSize: 'small',
            disabled: this.sameFile(),
            onTap: () => {
              const a = this.sources[this.srcIdx];
              const b = this.sources[this.tgtIdx];
              if (a !== undefined && b !== undefined && a.id !== b.id) {
                this.onConfirm(a.id, b.id);
              }
            },
          })
        }.width('100%').margin({ top: 2 })
      }.width('100%')
    }
  }
}

// ─── 添加文件弹窗 ──────────────────────────


@CustomDialog
struct AddFileDialogBuilder {
  controller: CustomDialogController;
  onConfirm: (label: string, path: string, uri: string) => void = (_l: string, _p: string, _u: string) => {};
  onCancel: () => void = () => {};
  @State localLabel: string = '';
  @State localPath: string = '';
  @State localUri: string = '';
  @State localError: string = '';

  /** 选择器返回的 URI → 回填路径/名称（选已有与新建共用） */
  private applyPickedUri(uri: string): void {
    this.localUri = uri;
    // file://docs/... URI → 真实路径（fileUri 解析；失败退回字符串截断）
    let path: string = '';
    try {
      const u: fileUri.FileUri = new fileUri.FileUri(uri);
      path = u.path;
    } catch (_) {
      path = uri.replace('file://', '');
    }
    if (path.length > 0) {
      this.localPath = path;
      if (this.localLabel === '') {
        const name: string = path.split('/').pop() ?? '';
        if (name !== '' && name !== '.') { this.localLabel = `~/${name}`; }
      }
      this.localError = '';
    }
  }

  /** 选已有文件：系统文件选择器（单选） */
  private browseFilePath(): void {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSelectOptions = {
        selectMode: picker.DocumentSelectMode.FILE,
        maxSelectNumber: 1,
      };
      docPicker.select(opts).then((uris: Array<string>) => {
        if (uris.length > 0) {
          this.applyPickedUri(uris[0]);
        }
      }).catch(() => {
      });
    } catch (e) {
      DevToast.show($r('app.string.env_manager_18'));
    }
  }

  /** 新建文件场景预填的默认文件名：显示名称末段 > .env */
  private suggestFileName(): string {
    const seg: string = this.localLabel.trim().split('/').pop() ?? '';
    return seg !== '' ? seg : '.env';
  }

  /** 新建文件：系统保存选择器（Picker 预置空文件并返回 URI，解决"文件不存在选不了"） */
  private createNewFile(): void {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSaveOptions = {
        newFileNames: [this.suggestFileName()],
        // 环境变量文件无固定后缀（.zshrc/.profile/自定义），不给 fileSuffixChoices
      };
      docPicker.save(opts).then((uris: Array<string>) => {
        if (uris.length > 0) {
          this.applyPickedUri(uris[0]);
        }
      }).catch(() => {
      });
    } catch (e) {
      DevToast.show($r('app.string.env_manager_19'));
    }
  }

  private tryConfirm(): void {
    const label: string = this.localLabel.trim();
    const path: string = this.localPath.trim();
    if (label.length === 0) { this.localError = '请输入文件名称'; return; }
    if (path.length === 0) { this.localError = '请先"选已有"或"新建"文件'; return; }
    // 主目录守卫（防御性：路径只能来自系统选择器，正常不会越界）
    if (!path.startsWith(HOME_PATH + '/')) {
      this.localError = `仅支持主目录（${HOME_PATH}）下的文件`;
      return;
    }
    this.localError = '';
    this.onConfirm(label, path, this.localUri);
  }

  build() {
    DevDialogPanel({
      title: '添加环境变量文件',
      dialogWidth: 480,
      paddingValueLeft: 24,
      paddingValueRight: 24,
      paddingValueTop: 16,
      paddingValueBottom: 24,
    }) {
      Column({ space: 16 }) {
        Column({ space: 6 }) {
          Text($r('app.string.env_manager_20')).fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_TERTIARY)
          DevInput({
            value: this.localLabel,
            placeholder: '如：~/.profile',
            mono: false,
            onChange: (v: string) => {
              this.localLabel = v;
              this.localError = '';
            },
          })
        }.width('100%').alignItems(HorizontalAlign.Start)

        // 文件区（用户设计稿）：路径直接跟随"文件："纯文本展示（非输入框样式——
        // 原路径槽带边框背景酷似可输入框，用户反馈误导），按钮独立一行
        Column({ space: 8 }) {
          if (this.localPath === '') {
            Text($r('app.string.env_manager_21'))
              .fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_MUTED)
              .width('100%')
          } else {
            Text() {
              Span('文件：').fontColor(DevTheme.TEXT_TERTIARY)
              Span(this.localPath)
                .fontColor(DevTheme.TEXT_PRIMARY)
                .fontFamily(DevTheme.MONO_FONT)
            }
            .fontSize(DevTheme.FS_BODY)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          }
          Row({ space: 8 }) {
            DevBtn({
              text: '选择',
              buttonSize: 'small',
              plain: true,
              onTap: () => {
                this.browseFilePath();
              },
            })
            DevBtn({
              text: '新建',
              buttonSize: 'small',
              plain: true,
              onTap: () => {
                this.createNewFile();
              },
            })
          }
          .width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)

        Text($r('app.string.env_manager_22'))
          .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED).width('100%')

        if (this.localError.length > 0) {
          Text(this.localError).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.DANGER)
        }

        Row({ space: 12 }) {
          Blank()
          DevBtn({ text: '取消', buttonSize: 'small', plain: true,
            onTap: () => { this.onCancel(); } })
          DevBtn({ text: '添加', buttonSize: 'small',
            onTap: () => { this.tryConfirm(); } })
        }.width('100%')
      }
      .width('100%')
    }
  }
}
