import os
import tempfile
import unittest

import wallpaper


class WallpaperTest(unittest.TestCase):
    def test_parse(self):
        txt = ("[Containments][4][Wallpaper][org.kde.image][General]\nImage=/usr/share/wallpapers/a.png\n"
               "PreviewImage=null\nImage=file:///home/x/b.jpg\nImage=/x/notimage.txt\nImage=/usr/share/wallpapers/a.png\n")
        self.assertEqual(wallpaper.parse(txt), ["/usr/share/wallpapers/a.png", "/home/x/b.jpg"])

    def test_current_prefers_user_file(self):
        with tempfile.TemporaryDirectory() as d:
            mine = os.path.join(d, "my wall.png")
            open(mine, "wb").close()
            rc = os.path.join(d, "rc")
            with open(rc, "w") as f:
                f.write("Image=/usr/share/none.png\nImage=file://%s\n" % mine)
            self.assertTrue(wallpaper.current(rc).endswith("my%20wall.png"))
            self.assertEqual(wallpaper.current(os.path.join(d, "yok")), "")


if __name__ == "__main__":
    unittest.main()
