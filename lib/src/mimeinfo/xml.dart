// Copyright 2026 The Authors. See the AUTHORS file for details.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:xml/xml.dart';

/// A root XML element match rule from the MIME database.
///
/// Matches a file by inspecting the namespace URI and/or local name of its
/// root XML element. Either field may be `null` to act as a wildcard.
class RootXML {
  /// The expected XML namespace URI of the root element, or `null` to match
  /// any namespace.
  final String? namespaceURI;

  /// The expected local name of the root element, or `null` to match any
  /// local name.
  final String? localName;

  /// The confidence weight of this rule (typically 50).
  final int weight;

  const RootXML({
    required this.namespaceURI,
    required this.localName,
    this.weight = 50,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RootXML &&
        other.namespaceURI == namespaceURI &&
        other.localName == localName &&
        other.weight == weight;
  }

  @override
  int get hashCode => Object.hash(namespaceURI, localName, weight);

  /// Check if a pre-parsed [XmlName] matches this rule's namespace and local name.
  bool matchesElement(XmlName name) {
    return name.local == localName && name.namespaceUri == namespaceURI;
  }

  /// Returns `true` if the root element of [bytes] matches this rule.
  ///
  /// Parses [bytes] as UTF-8 XML each call. For batch operations, prefer
  /// [matchesElement] with a pre-parsed [XmlName] to avoid repeated parsing.
  /// Returns `false` if [bytes] cannot be parsed as XML.
  bool matches(Uint8List bytes) {
    try {
      final document = XmlDocument.parse(utf8.decode(bytes));
      return matchesElement(document.rootElement.name);
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'namespaceURI': namespaceURI,
      'localName': localName,
      'weight': weight,
    };
  }

  @override
  String toString() => jsonEncode(toMap());
}
