class GlobalSettings {
  String anthropicKey;
  String openAiKey;
  String deepSeekKey;
  String tavilyKey;
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

  // Show message timestamp and/or short id on bubbles
  bool showBubbleTime;
  bool showBubbleId;

  // Hide the "добавить тезис" button on chat bubbles
  bool hideThesisButton;

  // Hide the compress (ПТ) button across chat / thesis / web-search / debug
  bool hideCompressButton;

  // Debug HTTP server (read-only introspection + screenshot)
  bool debugServerEnabled;
  int debugServerPort;
  String debugServerToken;

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
    this.tavilyKey = '',
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
    this.showBubbleTime = false,
    this.showBubbleId = false,
    this.hideThesisButton = false,
    this.hideCompressButton = false,
    this.debugServerEnabled = false,
    this.debugServerPort = 8080,
    this.debugServerToken = '',
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
        'tavilyKey': tavilyKey,
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
        'showBubbleTime': showBubbleTime,
        'showBubbleId': showBubbleId,
        'hideThesisButton': hideThesisButton,
        'hideCompressButton': hideCompressButton,
        'debugServerEnabled': debugServerEnabled,
        'debugServerPort': debugServerPort,
        'debugServerToken': debugServerToken,
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
        tavilyKey: j['tavilyKey'] as String? ?? '',
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
        showBubbleTime: j['showBubbleTime'] as bool? ?? false,
        showBubbleId: j['showBubbleId'] as bool? ?? false,
        hideThesisButton: j['hideThesisButton'] as bool? ?? false,
        hideCompressButton: j['hideCompressButton'] as bool? ?? false,
        debugServerEnabled: j['debugServerEnabled'] as bool? ?? false,
        debugServerPort: j['debugServerPort'] as int? ?? 8080,
        debugServerToken: j['debugServerToken'] as String? ?? '',
        tokensInAnthropicTotal: j['tokensInAnthropicTotal'] as int? ?? 0,
        tokensOutAnthropicTotal: j['tokensOutAnthropicTotal'] as int? ?? 0,
        tokensInOpenaiTotal: j['tokensInOpenaiTotal'] as int? ?? 0,
        tokensOutOpenaiTotal: j['tokensOutOpenaiTotal'] as int? ?? 0,
        tokensInDeepseekTotal: j['tokensInDeepseekTotal'] as int? ?? 0,
        tokensOutDeepseekTotal: j['tokensOutDeepseekTotal'] as int? ?? 0,
      );

  /// Копирует все поля из другого экземпляра.
  /// Используется когда settings — final поле в AppModel и нельзя переназначить.
  /// ВАЖНО: при добавлении новых полей — обновить здесь, иначе они не
  /// подгружаются при рестарте приложения.
  void copyFrom(GlobalSettings o) {
    anthropicKey = o.anthropicKey;
    openAiKey = o.openAiKey;
    deepSeekKey = o.deepSeekKey;
    tavilyKey = o.tavilyKey;
    defaultSystemPrompt = o.defaultSystemPrompt;
    useBuiltinSystemPrompt = o.useBuiltinSystemPrompt;
    streamingMode = o.streamingMode;
    showNodeLabels = o.showNodeLabels;
    renderMarkdown = o.renderMarkdown;
    hideEmoji = o.hideEmoji;
    defaultProvider = o.defaultProvider;
    defaultModel = o.defaultModel;
    defaultMaxTokens = o.defaultMaxTokens;
    defaultTemperature = o.defaultTemperature;
    compactChat = o.compactChat;
    compactLines = o.compactLines;
    showBubbleTime = o.showBubbleTime;
    showBubbleId = o.showBubbleId;
    hideThesisButton = o.hideThesisButton;
    hideCompressButton = o.hideCompressButton;
    debugServerEnabled = o.debugServerEnabled;
    debugServerPort = o.debugServerPort;
    debugServerToken = o.debugServerToken;
    tokensInAnthropicTotal = o.tokensInAnthropicTotal;
    tokensOutAnthropicTotal = o.tokensOutAnthropicTotal;
    tokensInOpenaiTotal = o.tokensInOpenaiTotal;
    tokensOutOpenaiTotal = o.tokensOutOpenaiTotal;
    tokensInDeepseekTotal = o.tokensInDeepseekTotal;
    tokensOutDeepseekTotal = o.tokensOutDeepseekTotal;
  }
}
