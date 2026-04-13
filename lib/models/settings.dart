class GlobalSettings {
  String anthropicKey;
  String openAiKey;
  String deepSeekKey;
  String defaultSystemPrompt;
  bool streamingMode;
  bool showNodeLabels;
  bool useBuiltinSystemPrompt;
  bool renderMarkdown;
  bool hideEmoji;

  // Default API node settings
  String defaultProvider;
  String defaultModel;
  int defaultMaxTokens;
  double defaultTemperature;

  // Compact chat
  bool compactChat;
  int compactLines;

  // Token usage totals (cumulative)
  int tokensInAnthropicTotal;
  int tokensOutAnthropicTotal;
  int tokensInOpenaiTotal;
  int tokensOutOpenaiTotal;
  int tokensInDeepseekTotal;
  int tokensOutDeepseekTotal;

  GlobalSettings({
    this.anthropicKey = '',
    this.openAiKey = '',
    this.deepSeekKey = '',
    this.defaultSystemPrompt = '',
    this.useBuiltinSystemPrompt = true,
    this.streamingMode = false,
    this.showNodeLabels = true,
    this.renderMarkdown = false,
    this.hideEmoji = false,
    this.defaultProvider = 'deepseek',
    this.defaultModel = 'deepseek-chat',
    this.defaultMaxTokens = 1024,
    this.defaultTemperature = 0.7,
    this.compactChat = false,
    this.compactLines = 5,
    this.tokensInAnthropicTotal = 0,
    this.tokensOutAnthropicTotal = 0,
    this.tokensInOpenaiTotal = 0,
    this.tokensOutOpenaiTotal = 0,
    this.tokensInDeepseekTotal = 0,
    this.tokensOutDeepseekTotal = 0,
  });

  Map<String, dynamic> toJson() => {
        'anthropicKey': anthropicKey,
        'openAiKey': openAiKey,
        'deepSeekKey': deepSeekKey,
        'defaultSystemPrompt': defaultSystemPrompt,
        'useBuiltinSystemPrompt': useBuiltinSystemPrompt,
        'streamingMode': streamingMode,
        'showNodeLabels': showNodeLabels,
        'renderMarkdown': renderMarkdown,
        'hideEmoji': hideEmoji,
        'defaultProvider': defaultProvider,
        'defaultModel': defaultModel,
        'defaultMaxTokens': defaultMaxTokens,
        'defaultTemperature': defaultTemperature,
        'compactChat': compactChat,
        'compactLines': compactLines,
        'tokensInAnthropicTotal': tokensInAnthropicTotal,
        'tokensOutAnthropicTotal': tokensOutAnthropicTotal,
        'tokensInOpenaiTotal': tokensInOpenaiTotal,
        'tokensOutOpenaiTotal': tokensOutOpenaiTotal,
        'tokensInDeepseekTotal': tokensInDeepseekTotal,
        'tokensOutDeepseekTotal': tokensOutDeepseekTotal,
      };

  factory GlobalSettings.fromJson(Map<String, dynamic> j) => GlobalSettings(
        anthropicKey: j['anthropicKey'] as String? ?? '',
        openAiKey: j['openAiKey'] as String? ?? '',
        deepSeekKey: j['deepSeekKey'] as String? ?? '',
        defaultSystemPrompt: j['defaultSystemPrompt'] as String? ?? '',
        useBuiltinSystemPrompt: j['useBuiltinSystemPrompt'] as bool? ?? true,
        streamingMode: j['streamingMode'] as bool? ?? false,
        showNodeLabels: j['showNodeLabels'] as bool? ?? true,
        renderMarkdown: j['renderMarkdown'] as bool? ?? false,
        hideEmoji: j['hideEmoji'] as bool? ?? false,
        defaultProvider: j['defaultProvider'] as String? ?? 'deepseek',
        defaultModel: j['defaultModel'] as String? ?? 'deepseek-chat',
        defaultMaxTokens: j['defaultMaxTokens'] as int? ?? 1024,
        defaultTemperature: (j['defaultTemperature'] as num?)?.toDouble() ?? 0.7,
        compactChat: j['compactChat'] as bool? ?? false,
        compactLines: j['compactLines'] as int? ?? 5,
        tokensInAnthropicTotal: j['tokensInAnthropicTotal'] as int? ?? 0,
        tokensOutAnthropicTotal: j['tokensOutAnthropicTotal'] as int? ?? 0,
        tokensInOpenaiTotal: j['tokensInOpenaiTotal'] as int? ?? 0,
        tokensOutOpenaiTotal: j['tokensOutOpenaiTotal'] as int? ?? 0,
        tokensInDeepseekTotal: j['tokensInDeepseekTotal'] as int? ?? 0,
        tokensOutDeepseekTotal: j['tokensOutDeepseekTotal'] as int? ?? 0,
      );
}
