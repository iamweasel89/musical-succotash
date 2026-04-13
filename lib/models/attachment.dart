class Attachment {
  final String filename;
  final String mimeType;
  final String base64Data;

  bool get isImage => mimeType.startsWith('image/');

  const Attachment({
    required this.filename,
    required this.mimeType,
    required this.base64Data,
  });

  Map<String, dynamic> toJson() => {
        'fn': filename,
        'mt': mimeType,
        'b64': base64Data,
      };

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        filename: j['fn'] as String,
        mimeType: j['mt'] as String,
        base64Data: j['b64'] as String,
      );
}
