import 'package:flutter_test/flutter_test.dart';
import 'package:scope_mobile/models.dart';
import 'package:scope_mobile/store.dart';

void main() {
  // web → client → site → blog (4 уровня), home отдельно.
  final store = AppStore()
    ..projects = const [
      Project(id: 1, name: 'web', position: 1),
      Project(id: 2, name: 'client', parentId: 1, avatar: '/media/a.png'),
      Project(id: 3, name: 'site', parentId: 2),
      Project(id: 4, name: 'blog', parentId: 3),
      Project(id: 5, name: 'home', position: 0, isPinned: true),
    ];

  test('tree is ordered with depth, pinned first', () {
    expect(store.projectTree().map((e) => '${e.$1.name}:${e.$2}').toList(),
        ['home:0', 'web:0', 'client:1', 'site:2', 'blog:3']);
  });

  test('depth, height, ancestors, descendants', () {
    final blog = store.projectById(4)!;
    expect(store.depthOf(blog), 3);
    expect(store.heightOf(store.projectById(1)!), 3);
    expect(store.ancestorsOf(blog).map((p) => p.name), ['web', 'client', 'site']);
    expect(store.descendantsOf(1), {2, 3, 4});
  });

  test('nesting limits and cycles', () {
    final web = store.projectById(1)!, site = store.projectById(3)!, blog = store.projectById(4)!;
    final home = store.projectById(5)!;
    expect(store.canNestUnder(blog, null), isFalse); // пятый уровень
    expect(store.canNestUnder(site, null), isTrue); // четвёртый
    expect(store.canNestUnder(site, web), isFalse); // цикл
    expect(store.canNestUnder(web, web), isFalse);
    expect(store.canNestUnder(home, store.projectById(2)!), isTrue); // client+2 уровня под home = 4
    expect(store.canNestUnder(store.projectById(2)!, home), isTrue);
  });

  test('avatar is inherited from the nearest ancestor', () {
    expect(store.avatarPath(store.projectById(4)!), '/media/a.png');
    expect(store.avatarPath(store.projectById(1)!), isNull);
  });
}
