import 'package:svgkit/src/editing/svg_references.dart';
import 'package:svgkit/src/model/svg_document.dart';
import 'package:svgkit/src/values/svg_aspect_ratio.dart';
import 'package:svgkit/src/values/svg_path.dart';
import 'package:svgkit/src/values/svg_style.dart';
import 'package:svgkit/src/values/svg_transform.dart';
import 'package:xml/xml.dart';

/// Transactional editing entry points on immutable document snapshots.
extension SvgDocumentEditing on SvgDocument {
  /// Applies synchronous edits to a copy and returns a validated new snapshot.
  ///
  /// If the callback or validation fails, this document remains unchanged.
  SvgDocument edit(void Function(SvgEditor editor) update, {SvgLimits limits = const SvgLimits()}) {
    final SvgEditor editor = SvgEditor(document: this, limits: limits);
    update(editor);
    return editor.build();
  }
}

/// An owned, mutable authoring session that produces immutable SVG snapshots.
final class SvgEditor {
  /// The private working tree, never aliased with an input or output document.
  final XmlDocument _xml;

  /// Limits applied when building snapshots or importing XML fragments.
  final SvgLimits limits;

  /// Stable element handles scoped to this session.
  final Map<XmlElement, SvgEditableElement> _handles = Map.identity();

  /// Copies an existing document for editing.
  SvgEditor({
    required SvgDocument document,
    this.limits = const SvgLimits(),
  }) : _xml = document.xml {
    if (limits.maxBytes <= 0 || limits.maxNodes <= 0 || limits.maxDepth <= 0) {
      throw ArgumentError('SVG limits must be positive.');
    }
  }

  /// Creates a blank SVG document with an optional viewport.
  factory SvgEditor.empty({
    SvgLength? width,
    SvgLength? height,
    SvgViewBox? viewBox,
    SvgLimits limits = const SvgLimits(),
  }) {
    final SvgEditor editor = SvgEditor(
      document: SvgDocument.parse(source: '<svg xmlns="$svgNamespace"/>'),
      limits: limits,
    );
    editor.root.setLength(name: 'width', value: width);
    editor.root.setLength(name: 'height', value: height);
    editor.root.setAttribute(name: 'viewBox', value: viewBox?.toString());
    return editor;
  }

  /// The working root element.
  SvgEditableElement get root => _handle(_xml.rootElement);

  /// All connected elements, including the root, in document order.
  List<SvgEditableElement> get elements => List.unmodifiable([root, ..._xml.rootElement.descendantElements.map(_handle)]);

  /// Finds a unique connected element, rejecting ambiguous duplicate IDs.
  SvgEditableElement? elementById({required String id}) {
    final List<SvgEditableElement> matches = elements.where((element) => element.id == id).toList();
    if (matches.length > 1) {
      throw StateError('Ambiguous SVG ID: $id.');
    }
    return matches.isEmpty ? null : matches.single;
  }

  /// Creates a detached element, including any SVG or extension element type.
  ///
  /// Attributes use qualified names. Declare extension prefixes explicitly in
  /// [attributes] or use [SvgEditableElement.setNamespacedAttribute].
  SvgEditableElement createElement({required String name, String namespace = svgNamespace, String? prefix, Map<String, String> attributes = const {}, String? text}) {
    _validateName(name);
    if (prefix != null) {
      _validateName(prefix);
    }
    final XmlElement node = XmlElement(XmlName.parts(name, prefix: prefix, namespaceUri: namespace.isEmpty ? null : namespace));
    node.setAttribute(prefix == null ? 'xmlns' : 'xmlns:$prefix', namespace);
    for (final MapEntry<String, String> attribute in attributes.entries.where((entry) => entry.key == 'xmlns' || entry.key.startsWith('xmlns:'))) {
      _writeAttribute(node: node, name: attribute.key, value: attribute.value);
    }
    for (final MapEntry<String, String> attribute in attributes.entries) {
      _writeAttribute(node: node, name: attribute.key, value: attribute.value);
    }
    if (text != null) {
      node.children.add(XmlText(text));
    }
    return _handle(node);
  }

  /// Imports a detached copy, preserving in-scope namespaces and extension data.
  ///
  /// Existing IDs are remapped by default. The returned element is not inserted;
  /// add it to a parent explicitly. References outside the imported tree stay
  /// external to it. [remapIds] false is useful when preserving known IDs.
  SvgEditableElement importElement({required XmlElement element, bool remapIds = true}) {
    _checkTreeLimits(root: element, limits: limits);
    final XmlElement copy = element.copy();
    _preserveNamespaces(source: element, destination: copy);
    final SvgEditableElement result = _handle(copy);
    if (remapIds) {
      _remapSubtree(copy);
    }
    return result;
  }

  /// Allocates an ID unused by connected and detached elements in this session.
  String uniqueId({String prefix = 'element'}) {
    _validateId(prefix);
    final Set<String> ids = _knownIds;
    if (!ids.contains(prefix)) {
      return prefix;
    }
    int suffix = 2;
    while (ids.contains('$prefix-$suffix')) {
      suffix++;
    }
    return '$prefix-$suffix';
  }

  /// Renames an attached element and updates recognized references document-wide.
  ///
  /// See [references] and the format reference for the explicit static reference
  /// scope. Scripts, external CSS and arbitrary attribute selectors are not
  /// interpreted. Renaming a detached element only updates its own subtree.
  void renameId({required SvgEditableElement element, required String id}) {
    _own(element);
    _validateId(id);
    if (element.id == id) {
      return;
    }
    if (_knownIds.contains(id)) {
      throw StateError('SVG ID already exists: $id.');
    }
    final String? old = element.id;
    if (old != null) {
      if (element.isConnected) {
        elementById(id: old); // Detect ambiguous imported IDs before changing links.
      }
      rewriteSvgReferences(root: element.isConnected ? _xml.rootElement : element._node, replacements: {old: id});
    }
    element._node.setAttribute('id', id);
  }

  /// Recognized href, URL, IDREF, timing and CSS ID-selector references.
  List<SvgLocalReference> get references => rewriteSvgReferences(root: _xml.rootElement);

  /// Recognized references whose targets do not exist in this document.
  List<SvgLocalReference> get danglingReferences {
    final Set<String> ids = elements.map((element) => element.id).whereType<String>().toSet();
    return List.unmodifiable(references.where((reference) => !ids.contains(reference.targetId)));
  }

  /// Duplicates a subtree beside its source and remaps all its IDs and local links.
  ///
  /// Stylesheets outside the subtree are not duplicated. CSS ID-based rules may
  /// need explicit edits to style the new IDs. Root duplication is disallowed.
  SvgEditableElement duplicate({required SvgEditableElement element}) {
    _own(element);
    final SvgEditableElement? parent = element.parent;
    if (parent == null) {
      throw StateError('Only parented SVG elements can be duplicated.');
    }
    final SvgEditableElement clone = importElement(element: element._node);
    parent.insert(child: clone, index: parent.children.indexOf(element) + 1);
    return clone;
  }

  /// Groups contiguous sibling elements, preserving their document order.
  ///
  /// This is a structural edit: CSS child selectors, inheritance and compositing
  /// can change. Whitespace/comments between selected elements move with them.
  SvgEditableElement group({required Iterable<SvgEditableElement> selection, String? id}) {
    final List<SvgEditableElement> selected = selection.toList();
    if (selected.isEmpty || selected.toSet().length != selected.length) {
      throw ArgumentError('A group requires distinct sibling elements.');
    }
    selected.forEach(_own);
    final SvgEditableElement? parent = selected.first.parent;
    if (parent == null || selected.any((element) => element.parent != parent)) {
      throw ArgumentError('A group requires elements with the same parent.');
    }
    final List<SvgEditableElement> siblings = parent.children;
    selected.sort((a, b) => siblings.indexOf(a).compareTo(siblings.indexOf(b)));
    final int first = siblings.indexOf(selected.first);
    if (siblings.indexOf(selected.last) - first + 1 != selected.length) {
      throw ArgumentError('Grouping noncontiguous siblings would change painting order.');
    }
    if (id != null) {
      _validateId(id);
      if (_knownIds.contains(id)) {
        throw StateError('SVG ID already exists: $id.');
      }
    }
    final SvgEditableElement group = createElement(name: 'g', attributes: {'id': ?id});
    final int from = parent._node.children.indexOf(selected.first._node);
    final int to = parent._node.children.indexOf(selected.last._node) + 1;
    final List<XmlNode> nodes = parent._node.children.sublist(from, to);
    for (final SvgEditableElement element in selected) {
      _preserveNamespaces(source: element._node, destination: element._node);
    }
    parent._node.children.removeRange(from, to);
    group._node.children.addAll(nodes);
    parent._node.children.insert(from, group._node);
    return group;
  }

  /// Removes a structural wrapper and retains its children in place.
  ///
  /// Requires explicit opt-in if the group has attributes beyond an ID/namespace,
  /// because removing transforms, opacity, styles or effects changes appearance.
  /// Even plain wrappers can affect selectors and references; this is not a
  /// rendering-preserving flatten operation.
  void ungroup({required SvgEditableElement group, bool discardGroupAttributes = false}) {
    _own(group);
    final SvgEditableElement? parent = group.parent;
    if (group.name != 'g' || parent == null) {
      throw ArgumentError('Expected a parented SVG group.');
    }
    if (!discardGroupAttributes && group._node.attributes.any((attribute) => attribute.name.qualified != 'id' && !(attribute.name.prefix == 'xmlns' || attribute.name.qualified == 'xmlns'))) {
      throw StateError('Ungrouping requires explicit handling of group attributes.');
    }
    for (final SvgEditableElement child in group.children) {
      _preserveNamespaces(source: child._node, destination: child._node);
    }
    final int index = parent._node.children.indexOf(group._node);
    final List<XmlNode> children = group._node.children.toList();
    group._node.children.clear();
    parent._node.children.removeAt(index);
    parent._node.children.insertAll(index, children);
  }

  /// Returns the first root defs element, creating it if necessary.
  SvgEditableElement get definitions {
    for (final SvgEditableElement child in root.children) {
      if (child.name == 'defs' && child.namespace == svgNamespace) {
        return child;
      }
    }
    final SvgEditableElement definitions = createElement(name: 'defs');
    root.insert(child: definitions, index: 0);
    return definitions;
  }

  /// Validates and copies the current state into an immutable document.
  ///
  /// Duplicate IDs are rejected by default; pre-existing malformed documents
  /// can be retained with [validateIds] false. Dangling links remain authorable
  /// and can be inspected separately with [danglingReferences].
  SvgDocument build({bool validateIds = true}) {
    _checkTreeLimits(root: _xml, limits: limits);
    if (validateIds) {
      final Set<String> ids = {};
      for (final SvgEditableElement element in elements) {
        final String? id = element.id;
        if (id != null && !ids.add(id)) {
          throw StateError('Duplicate SVG ID: $id.');
        }
      }
    }
    return SvgDocument.fromXml(document: _xml, limits: limits);
  }

  /// Returns or creates a stable handle for an owned node.
  SvgEditableElement _handle(XmlElement node) => _handles.putIfAbsent(node, () => SvgEditableElement._(editor: this, node: node));

  /// Rejects handles belonging to another session.
  void _own(SvgEditableElement element) {
    if (!identical(element._editor, this)) {
      throw ArgumentError('SVG element belongs to another editing session.');
    }
  }

  /// IDs of every known subtree, including detached nodes awaiting insertion.
  Set<String> get _knownIds => {
    for (final XmlElement node in [_xml.rootElement, ..._xml.rootElement.descendantElements, ..._handles.keys])
      for (final XmlElement nested in [node, if (node.parent == null) ...node.descendantElements])
        if (nested.getAttribute('id') case final String id) id,
  };

  /// Gives every imported ID a unique value and rewrites intra-subtree links.
  void _remapSubtree(XmlElement root) {
    final Map<String, String> replacements = {};
    final Set<String> seen = {};
    final Set<String> reserved = _knownIds;
    for (final XmlElement node in [root, ...root.descendantElements]) {
      final String? id = node.getAttribute('id');
      if (id == null) {
        continue;
      }
      if (!seen.add(id)) {
        throw StateError('Cannot remap ambiguous duplicate ID: $id.');
      }
      String candidate = '$id-copy';
      int suffix = 2;
      while (reserved.contains(candidate)) {
        candidate = '$id-copy-${suffix++}';
      }
      reserved.add(candidate);
      replacements[id] = candidate;
    }
    rewriteSvgReferences(root: root, replacements: replacements, renameIds: true);
  }
}

/// Checks tree depth and node/character lower bounds before recursive copying.
///
/// The codec's XML-event and UTF-8 checks enforce exact serialized limits after
/// this preflight. This pass prevents an oversized edited tree reaching a
/// recursive serializer first.
void _checkTreeLimits({required XmlNode root, required SvgLimits limits}) {
  final List<({XmlNode node, int depth})> pending = [(node: root, depth: 0)];
  int nodes = 0;
  int characters = 0;
  while (pending.isNotEmpty) {
    final ({XmlNode node, int depth}) current = pending.removeLast();
    if (current.node is! XmlDocument) {
      nodes++;
    }
    if (nodes > limits.maxNodes) {
      throw const FormatException('Edited SVG exceeds the node limit.');
    }
    final XmlNode node = current.node;
    final int depth = current.depth + (node is XmlElement ? 1 : 0);
    if (depth > limits.maxDepth) {
      throw const FormatException('Edited SVG exceeds the nesting limit.');
    }
    characters += node.value?.length ?? 0;
    if (node is XmlElement) {
      characters += node.name.qualified.length;
      for (final XmlAttribute attribute in node.attributes) {
        characters += attribute.name.qualified.length + attribute.value.length;
      }
    }
    if (characters > limits.maxBytes || pending.length + node.children.length + nodes > limits.maxNodes) {
      throw const FormatException('Edited SVG exceeds the document/node limit.');
    }
    for (final XmlNode child in node.children) {
      pending.add((node: child, depth: depth));
    }
  }
}

/// A stable editable element handle owned by one [SvgEditor].
final class SvgEditableElement {
  /// Owning session.
  final SvgEditor _editor;

  /// Private working element.
  final XmlElement _node;

  /// Creates a session-owned handle.
  SvgEditableElement._({
    required this._editor,
    required this._node,
  });

  /// Local XML element name, including unknown extension names.
  String get name => _node.name.local;

  /// Resolved namespace URI.
  String? get namespace => _node.namespaceUri;

  /// Optional exact element ID.
  String? get id => _node.getAttribute('id');

  /// Space-separated CSS classes, without duplicate tokens.
  Set<String> get classes => Set.unmodifiable((attribute(name: 'class') ?? '').split(RegExp(r'\s+')).where((value) => value.isNotEmpty));

  /// Replaces CSS class tokens without interpreting stylesheet rules.
  void setClasses({required Iterable<String> values}) {
    final Set<String> tokens = values.toSet();
    if (tokens.any((token) => token.isEmpty || token.contains(RegExp(r'\s')))) {
      throw ArgumentError('CSS classes must be nonempty individual tokens.');
    }
    setAttribute(name: 'class', value: tokens.join(' '));
  }

  /// Optional viewBox on an SVG viewport, symbol, marker or pattern.
  SvgViewBox? get viewBox {
    final String? value = attribute(name: 'viewBox');
    return value == null ? null : SvgViewBox.parse(value: value);
  }

  /// Sets or removes the element's viewport rectangle.
  void setViewBox({required SvgViewBox? value}) => setAttribute(name: 'viewBox', value: value?.toString());

  /// Viewport fitting syntax, using SVG's default when the attribute is absent.
  SvgPreserveAspectRatio get preserveAspectRatio {
    final String? value = attribute(name: 'preserveAspectRatio');
    return value == null ? SvgPreserveAspectRatio() : SvgPreserveAspectRatio.parse(source: value);
  }

  /// Sets or removes the viewport fitting rule.
  void setPreserveAspectRatio({required SvgPreserveAspectRatio? value}) => setAttribute(name: 'preserveAspectRatio', value: value?.toString());

  /// Whether the element is currently part of the editor document.
  bool get isConnected => identical(_node.root, _editor._xml);

  /// Parent element, or null for the document root and detached elements.
  SvgEditableElement? get parent => _node.parent is XmlElement ? _editor._handle(_node.parent! as XmlElement) : null;

  /// Stable handles for immediate child elements, excluding text and comments.
  List<SvgEditableElement> get children => List.unmodifiable(_node.childElements.map(_editor._handle));

  /// Stable handles for every descendant element in document order.
  List<SvgEditableElement> get descendants => List.unmodifiable(_node.descendantElements.map(_editor._handle));

  /// Qualified attributes as an immutable snapshot.
  Map<String, String> get attributes => Map.unmodifiable({for (final XmlAttribute attribute in _node.attributes) attribute.name.qualified: attribute.value});

  /// Detached XML copy for inspection or later import.
  XmlElement get xml {
    final XmlElement copy = _node.copy();
    _preserveNamespaces(source: _node, destination: copy);
    return copy;
  }

  /// Reads an exact qualified attribute or one matched by namespace URI.
  String? attribute({required String name, String? namespace}) => _node.getAttribute(name, namespaceUri: namespace);

  /// Sets or removes any attribute without interpreting unknown values.
  ///
  /// Direct ID changes do not rewrite links; use [SvgEditor.renameId] for that.
  void setAttribute({required String name, required String? value}) => _writeAttribute(node: _node, name: name, value: value);

  /// Sets an extension attribute and declares its namespace locally.
  void setNamespacedAttribute({required String name, required String prefix, required String namespace, required String? value}) {
    _validateName(name);
    _validateName(prefix);
    if (prefix == 'xmlns' || (prefix == 'xml' && namespace != 'http://www.w3.org/XML/1998/namespace')) {
      throw ArgumentError('Reserved XML prefix.');
    }
    final String? existing = _node.namespaces.where((binding) => binding.prefix == prefix).firstOrNull?.uri;
    if (existing != null && existing != namespace) {
      throw ArgumentError('Prefix already belongs to another namespace.');
    }
    if (value != null) {
      _node.setAttribute('xmlns:$prefix', namespace);
    }
    _writeAttribute(node: _node, name: '$prefix:$name', value: value);
  }

  /// Reads a typed geometric length without resolving layout.
  SvgLength? length({required String name}) {
    final String? value = attribute(name: name);
    return value == null || value == 'auto' ? null : SvgLength.parse(value: value);
  }

  /// Sets or removes a typed geometric length.
  void setLength({required String name, required SvgLength? value}) => setAttribute(name: name, value: value?.toString());

  /// Path commands; absent path data is an empty path.
  SvgPathData get pathData => SvgPathData.parse(source: attribute(name: 'd') ?? '');

  /// Replaces path commands without modifying styles, transforms or metadata.
  void setPathData({required SvgPathData value}) => setAttribute(name: 'd', value: value.toString());

  /// Polygon/polyline coordinate pairs; an absent list is empty.
  SvgPointList get points => SvgPointList.parse(source: attribute(name: 'points') ?? '');

  /// Replaces polygon/polyline coordinates.
  void setPoints({required SvgPointList value}) => setAttribute(name: 'points', value: value.toString());

  /// Parses a transform, gradientTransform or patternTransform attribute.
  SvgTransformList transforms({String attribute = 'transform'}) => SvgTransformList.parse(source: this.attribute(name: attribute) ?? '');

  /// Replaces a transform list, including paint-server transforms.
  void setTransforms({required SvgTransformList value, String attribute = 'transform'}) => setAttribute(name: attribute, value: value.toString());

  /// Specified inline CSS, retaining unrelated source fragments during edits.
  SvgStyle get style => SvgStyle(source: attribute(name: 'style') ?? '');

  /// Replaces the specified inline style block.
  void setStyle({required SvgStyle value}) => setAttribute(name: 'style', value: value.toString());

  /// Sets one inline CSS property without losing other declarations.
  void setStyleProperty({required String name, required String value, bool important = false}) => setStyle(
    value: style.set(name: name, value: value, important: important),
  );

  /// Removes all inline declarations of a property, exposing the cascade below.
  void removeStyleProperty({required String name}) => setStyle(value: style.remove(name: name));

  /// SVG 2 href takes precedence over the legacy XLink attribute.
  String? get href => attribute(name: 'href') ?? attribute(name: 'href', namespace: svgXlinkNamespace);

  /// Updates href and any existing legacy XLink href to prevent stale links.
  void setHref({required String? value, bool includeXlink = false}) {
    setAttribute(name: 'href', value: value);
    final XmlAttribute? legacy = _node.getAttributeNode('href', namespaceUri: svgXlinkNamespace);
    if (legacy != null) {
      _node.setAttribute(legacy.name.qualified, value);
    } else if (includeXlink) {
      setNamespacedAttribute(name: 'href', prefix: 'xlink', namespace: svgXlinkNamespace, value: value);
    }
  }

  /// Links to a same-session resource, assigning it an ID when necessary.
  ///
  /// `href` uses a fragment URI; other properties use an inline CSS URL so an
  /// existing ordinary inline declaration cannot hide the edit. The target may
  /// be detached while authoring; insert it into definitions before building.
  void setReference({required String property, required SvgEditableElement target}) {
    _editor._own(target);
    if (svgHasExplicitBase(_node)) {
      throw StateError('Resolve explicit xml:base in the host before assigning local resource links.');
    }
    if (target.id == null) {
      _editor.renameId(
        element: target,
        id: _editor.uniqueId(prefix: target.name),
      );
    }
    final String uri = '#${Uri.encodeComponent(target.id!)}';
    if (property == 'href') {
      setHref(value: uri);
    } else {
      setStyleProperty(name: property, value: 'url("$uri")');
    }
  }

  /// Resolves a fragment-only href against this editing session, without I/O.
  SvgEditableElement? get hrefTarget {
    final String? value = href?.trim();
    if (value == null || !value.startsWith('#') || svgHasExplicitBase(_node)) {
      return null;
    }
    final String? id = decodeSvgFragment(value.substring(1));
    return id == null ? null : _editor.elementById(id: id);
  }

  /// Concatenated descendant text, including tspan/textPath text runs.
  String get text => _node.innerText;

  /// Replaces all content with one text node; removes existing spans/elements.
  ///
  /// Use [replaceTextRun] to edit a run while retaining rich text structure.
  void setText({required String value}) {
    _node.children.clear();
    _node.children.add(XmlText(value));
  }

  /// Immediate text and CDATA runs, retaining their spacing and source order.
  List<String> get textRuns => List.unmodifiable(_node.children.where((node) => node is XmlText || node is XmlCDATA).map((node) => node.value!));

  /// Replaces one immediate run without changing spans, comments or text paths.
  void replaceTextRun({required int index, required String value}) {
    final List<XmlNode> runs = _node.children.where((node) => node is XmlText || node is XmlCDATA).toList();
    final XmlNode old = runs[index];
    _node.children[_node.children.indexOf(old)] = XmlText(value);
  }

  /// Appends a text run, useful for mixed text/tspan/textPath authoring.
  void appendText({required String value}) => _node.children.add(XmlText(value));

  /// Replaces mixed XML content with detached copies of supplied nodes.
  ///
  /// Supports comments, text, CDATA, processing instructions and extension
  /// elements. Existing child handles become detached. Build validates the XML.
  void replaceContent({required Iterable<XmlNode> nodes}) {
    final List<XmlNode> copies = nodes.map((node) {
      final XmlNode copy = node.copy();
      if (node is XmlElement && copy is XmlElement) {
        _preserveNamespaces(source: node, destination: copy);
      }
      return copy;
    }).toList();
    // Validate the allowed XML child types before clearing the current content.
    final XmlElement holder = XmlElement(const XmlName.parts('holder'), [], copies);
    holder.children.clear();
    _node.children.clear();
    _node.children.addAll(copies);
  }

  /// Inserts or moves a same-session element at a final element-child index.
  ///
  /// Omitted index appends after all mixed content. Moving across groups keeps
  /// local attributes; world coordinates, CSS and compositing can change.
  void insert({required SvgEditableElement child, int? index}) {
    _editor._own(child);
    if (identical(child._node, _editor._xml.rootElement)) {
      throw ArgumentError('Cannot reparent the SVG root.');
    }
    if (identical(child, this) || _node.ancestors.contains(child._node)) {
      throw ArgumentError('Cannot create an XML ancestry cycle.');
    }
    final List<XmlElement> remaining = _node.childElements.where((element) => !identical(element, child._node)).toList();
    final int target = index ?? remaining.length;
    RangeError.checkValueInInterval(target, 0, remaining.length, 'index');
    _preserveNamespaces(source: child._node, destination: child._node);
    child._node.parent?.children.remove(child._node);
    final int offset = target == remaining.length ? _node.children.length : _node.children.indexOf(remaining[target]);
    _node.children.insert(offset, child._node);
  }

  /// Removes this subtree while retaining its handle for possible reinsertion.
  ///
  /// References are retained and become visible through danglingReferences.
  void remove() {
    if (identical(_node, _editor._xml.rootElement)) {
      throw StateError('Cannot remove the SVG root.');
    }
    _preserveNamespaces(source: _node, destination: _node);
    _node.parent?.children.remove(_node);
  }
}

/// Copies inherited namespace bindings before detaching or moving a subtree.
void _preserveNamespaces({required XmlElement source, required XmlElement destination}) {
  final Map<String, String> namespaces = {for (final XmlNamespace namespace in source.namespaces) namespace.prefix: namespace.uri};
  for (final MapEntry<String, String> namespace in namespaces.entries) {
    if (namespace.key != 'xml') {
      destination.setAttribute(namespace.key.isEmpty ? 'xmlns' : 'xmlns:${namespace.key}', namespace.value);
    }
  }
  // An unnamespaced subtree moved under an SVG default namespace must stay so.
  if (!namespaces.containsKey('') && source.name.prefix == null && source.namespaceUri == null) {
    destination.setAttribute('xmlns', '');
  }
  // Detached lookup copies can retain resolved XmlName URIs while losing the
  // ancestor declarations. Reconstruct only bindings needed by actual names.
  for (final XmlElement element in [destination, ...destination.descendantElements]) {
    final Map<String, String> bindings = {for (final XmlNamespace binding in element.namespaces) binding.prefix: binding.uri};
    for (final XmlName name in [element.name, ...element.attributes.where((attribute) => !(attribute.name.prefix == 'xmlns' || attribute.name.qualified == 'xmlns')).map((attribute) => attribute.name)]) {
      final String? uri = name.namespaceUri;
      if (uri != null && bindings[name.prefix ?? ''] != uri) {
        element.setAttribute(name.prefix == null ? 'xmlns' : 'xmlns:${name.prefix}', uri);
        bindings[name.prefix ?? ''] = uri;
      }
    }
    if (element.name.prefix == null && element.namespaceUri == null && bindings.containsKey('')) {
      element.setAttribute('xmlns', '');
    }
  }
}

/// Validates an unqualified name before constructing authoring elements.
void _validateName(String name) {
  // Let the XML parser validate the full Unicode XML name grammar.
  if (name.contains(':') || name.contains(RegExp(r'[\s<>/="\x27]'))) {
    throw ArgumentError.value(name, 'name', 'Expected an unqualified XML name.');
  }
  XmlDocument.parse('<$name/>');
}

/// Validates an SVG 2 ID without restricting it to ASCII identifiers.
void _validateId(String id) {
  if (id.isEmpty || id.contains(RegExp(r'[\s\x00-\x1f]'))) {
    throw ArgumentError.value(id, 'id', 'IDs must be nonempty and contain no whitespace or controls.');
  }
}

/// Writes qualified attributes with resolved namespace metadata in the live tree.
void _writeAttribute({required XmlElement node, required String name, required String? value}) {
  final int colon = name.indexOf(':');
  final String? prefix = colon < 0 ? null : name.substring(0, colon);
  _validateName(colon < 0 ? name : name.substring(colon + 1));
  if (prefix != null) {
    _validateName(prefix);
  }
  final bool declaration = prefix == 'xmlns' || name == 'xmlns';
  final XmlAttribute? old = node.getAttributeNode(name);
  if (declaration && old != null && old.value != value) {
    throw ArgumentError('Rebinding an existing namespace requires explicit XML replacement.');
  }
  if (old != null) {
    if (value == null) {
      node.attributes.remove(old);
    } else {
      old.value = value;
    }
    return;
  }
  if (value == null) {
    return;
  }
  final String? uri = declaration
      ? 'http://www.w3.org/2000/xmlns/'
      : prefix == null
      ? null
      : node.namespaces.where((binding) => binding.prefix == prefix).firstOrNull?.uri;
  if (prefix != null && uri == null) {
    throw ArgumentError('Undeclared attribute namespace prefix: $prefix.');
  }
  node.attributes.add(XmlAttribute(XmlName.qualified(name, namespaceUri: uri), value));
}
