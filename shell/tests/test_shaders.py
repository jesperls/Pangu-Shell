from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SHELL = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("qsb"), "Qt Shader Baker is required")
class ShaderFormatsTest(unittest.TestCase):
    def test_built_shaders_support_opengl_and_vulkan(self):
        shaders = sorted(path for path in SHELL.rglob("*") if path.suffix in (".frag", ".vert"))
        self.assertTrue(shaders)
        with tempfile.TemporaryDirectory(prefix="pangu-shaders-") as directory:
            output = Path(directory) / "shader"
            for shader in shaders:
                pack = shader.with_suffix(shader.suffix + ".qsb")
                with self.subTest(shader=shader.relative_to(SHELL)):
                    self.assertTrue(pack.is_file(), f"Shader was not baked: {pack}")
                    for target in ("glsl,100 es", "glsl,150", "spirv,100"):
                        result = subprocess.run(
                            ["qsb", "--extract", target, str(pack), "-o", str(output)],
                            capture_output=True, text=True, timeout=5,
                        )
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertGreater(output.stat().st_size, 0)
                        output.unlink()
