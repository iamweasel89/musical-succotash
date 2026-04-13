class GlobalSettings {
  String anthropicKey;
  String openAiKey;
  String deepSeekKey;
  String defaultSystemPrompt;
  bool streamingMode;
  bool showNodeLabels;

  // Default API node settings
  String defaultProvider;
  String defaultModel;
  int defaultMaxTokens;
  double defaultTemperature;

  // Compact chat
  bool compactChat;
  int compactLines;

  GlobalSettings({
    this.anthropicKey = '',
    this.openAiKey = '',
    this.deepSeekKey = '',
    this.defaultSystemPrompt = '',
    this.streamingMode = false,
    this.showNodeLabels = true,
    this.defaultProvider = 'deepseek',
    this.defaultModel = 'deepseek-chat',
    this.defaultMaxTokens = 1024,
    this.defaultTemperature = 0.7,
    this.compactChat = false,
    this.compactLines = 5,
  });

  Map<String, dynamic> toJson() => {
        'anthropicKey': anthropicKey,
        'openAiKey': openAiKey,
        'deepSeekKey': deepSeekKey,
        'defaultSystemPrompt': defaultSystemPrompt,
        'streamingMode': streamingMode,
        'showNodeLabels': showNodeLabels,
        'defaultProvider': defaultProvider,
        'defaultModel': defaultModel,
        'defaultMaxTokens': defaultMaxTokens,
        'defaultTemperature': defaultTemperature,
        'compactChat': compactChat,
        'compactLines': compactLines,
      };

  factory GlobalSettings.fromJson(Map<String, dynamic> j) => GlobalSettings(
        anthropicKey: j['anthropicKey'] as String? ?? '',
        openAiKey: j['openAiKey'] as String? ?? '',
        deepSeekKey: j['deepSeekKey'] as String? ?? '',
        defaultSystemPrompt: j['defaultSystemPrompt'] as String? ?? '',
        streamingMode: j['streamingMode'] as bool? ?? false,
        showNodeLabels: j['showNodeLabels'] as bool? ?? true,
        defaultProvider: j['defaultProvider'] as String? ?? 'deepseek',
        defaultModel: j['defaultModel'] as String? ?? 'deepseek-chat',
        defaultMaxTokens: j['defaultMaxTokens'] as int? ?? 1024,
        defaultTemperature: (j['defaultTemperature'] as num?)?.toDouble() ?? 0.7,
        compactChat: j['compactChat'] as bool? ?? false,
        compactLines: j['compactLines'] as int? ?? 5,
      );
}
