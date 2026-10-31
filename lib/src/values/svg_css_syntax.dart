/// CSS identifiers, including escaped code points and non-ASCII characters.
final RegExp svgCssIdentifier = RegExp(r'(?:[-_a-zA-Z0-9\u0080-\uffff]|\\(?:[0-9a-fA-F]{1,6}[ \t\r\n\f]?|[^\r\n\f]))+');

/// Decodes CSS escapes in identifiers and quoted/unquoted URL arguments.
String decodeSvgCssEscapes(String source) => source.replaceAllMapped(RegExp(r'\\(?:([0-9a-fA-F]{1,6})(?:\r\n|[ \t\r\n\f])?|([^\r\n\f]))'), (match) {
  final String? digits = match[1];
  if (digits == null) {
    return match[2]!;
  }
  final int code = int.parse(digits, radix: 16);
  return String.fromCharCode(code == 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) ? 0xfffd : code);
});
