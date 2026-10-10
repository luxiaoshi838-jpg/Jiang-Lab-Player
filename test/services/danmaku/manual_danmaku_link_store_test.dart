import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/danmaku/manual_danmaku_link_store.dart';

void main() {
  test('links use a work identity and are independent of video source URL', () {
    expect(ManualDanmakuLinkStore.keyFor(127), 'vodDanmakuLinkV1_127');
    final input = {1: 10031, 46: 10076};
    final encoded = ManualDanmakuLinkStore.encode(input);
    expect(encoded, ['1:10031', '46:10076']);
    expect(ManualDanmakuLinkStore.decode(encoded), input);
  });

  test('malformed and invalid persisted entries are ignored safely', () {
    final links = ManualDanmakuLinkStore.decode([
      '1:123', 'broken', '2:-5', '0:88', '3:no', '1:456',
    ]);
    expect(links, {1: 456});
  });

  test('separate episode numbers never share the same mapping accidentally', () {
    const one = 901;
    const two = 902;
    final links = ManualDanmakuLinkStore.decode(
      ManualDanmakuLinkStore.encode({1: one, 2: two}),
    );
    expect(links[1], one);
    expect(links[2], two);
    expect(links[3], isNull);
  });
}
