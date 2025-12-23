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
  isNeedHide?: boolean = false;
}