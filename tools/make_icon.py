"""Pack assets/icon/icon_<n>.png (from tools/make_icon.gd) into assets/icon/realmlings.ico for the Windows build."""
from PIL import Image
sizes = [16, 24, 32, 48, 64, 128, 256]
big = Image.open('assets/icon/icon_256.png').convert('RGBA')
big.save('assets/icon/realmlings.ico', sizes=[(n, n) for n in sizes],
         append_images=[Image.open(f'assets/icon/icon_{n}.png').convert('RGBA') for n in sizes[:-1]])
print('assets/icon/realmlings.ico')
