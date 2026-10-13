/// Per-plugin search progress, written solely by PluginSearchService.
enum PluginSearchStatus { pending, success, error, noResult, captcha }

class SearchItem {
  String name;
  String src;
  String imageUrl;

  SearchItem({
    required this.name,
    required this.src,
    this.imageUrl = '',
  });

  factory SearchItem.fromJson(Map<String, dynamic> json) {
    return SearchItem(
      name: json['name'], src: json['src'],
      imageUrl: json['imageUrl'] as String? ?? '',
    );
  }
}

class PluginSearchResponse {
  String pluginName;
  List<SearchItem> data;

  PluginSearchResponse({
    required this.pluginName,
    required this.data,
  });

  factory PluginSearchResponse.fromJson(Map<String, dynamic> json) {
    return PluginSearchResponse(
      pluginName: json['pluginName'],
      data: (json['data'] as List)
          .map((itemJson) => SearchItem.fromJson(itemJson))
          .toList(),
    );
  }
}
