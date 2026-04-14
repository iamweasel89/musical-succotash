class Attachment {
  final String filename;
  final String mimeType;
  final String? base64Data;   // set for images
  final String? textContent;  // set for text/document files

  bool get isImage => mimeType.startsWith('image/');
  bool get isText => textContent != null;

  const Attachment({
    required this.filename,
    required this.mimeType,
    this.base64Data,
    this.textContent,
  }) : assert(base64Data != null || textContent != null,
            'Attachment must have either base64Data or textContent');

  Map<String, dynamic> toJson() => {
        'fn': filename,
        'mt': mimeType,
        if (base64Data != null) 'b64': base64Data,
        if (textContent != null) 'txt': textContent,
      };

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        filename: j['fn'] as String,
        mimeType: j['mt'] as String,
        base64Data: j['b64'] as String?,
        textContent: j['txt'] as String?,
      );
}
