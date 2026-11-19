import json
import os
import sys

src = sys.argv[1]
out = os.path.join(src, 'filelist.json')

files = []
total = 0
for root, dirs, names in os.walk(src):
    dirs.sort()
    names.sort()
    for name in names:
        if name == 'filelist.json':
            continue
        path = os.path.join(root, name)
        rel = os.path.relpath(path, src).replace(os.sep, '/')
        try:
            size = os.path.getsize(path)
        except OSError:
            continue
        files.append({'p': rel, 's': size})
        total += size

with open(out, 'w', encoding='utf-8') as f:
    json.dump({'files': files, 'count': len(files), 'total': total}, f, ensure_ascii=False)

print('wrote %s' % out)
print('%d files, %.2f GB' % (len(files), total / 1e9))
