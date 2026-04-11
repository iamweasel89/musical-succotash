class GlobalSettings {
  String anthropicKey;
  String openAiKey;
  String deepSeekKey;
  String defaultSystemPrompt;
  bool streamingMode;

  GlobalSettings({
    this.anthropicKey = '',
    this.openAiKey = '',
    this.deepSeekKey = '',
    this.defaultSystemPrompt = '',
    this.streamingMode = false,
  });

  Map<String, dynamic> toJson() => {
        'anthropicKey': anthropicKey,
        'openAiKey': openAiKey,
        'deepSeekKey': deepSeekKey,
        'defaultSystemPrompt': defaultSystemPrompt,
        'streamingMode': streamingMode,
      };

  factory GlobalSettings.fromJson(Map<String, dynamic> j) => GlobalSettings(
        anthropicKey: j['anthropicKey'] as String? ?? '',
        openAiKey: j['openAiKey'] as String? ?? '',
        deepSeekKey: j['deepSeekKey'] as String? ?? '',
        defaultSystemPrompt: j['defaultSystemPrompt'] as String? ?? '',
        streamingMode: j['streamingMode'] as bool? ?? false,
      );
}
