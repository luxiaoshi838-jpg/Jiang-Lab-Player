"""No real signing keys are used by these public unit tests."""
import importlib.util
import io
import pathlib
import tempfile
import unittest
import zipfile

FILE = pathlib.Path(__file__).resolve().parents[1] / "private_android_release.py"
spec = importlib.util.spec_from_file_location("private_android_release", FILE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def credentials():
    return (
        "应用: 随播\n"
        "Key alias: demo\n"
        "Key store: suibo-release.jks\n"
        "Store password: test-example-only\n"
        "Key password: test-example-only-2\n"
    ).encode()


class PrivateSigningTests(unittest.TestCase):
    def test_parse_credential_fields_without_disclosing_values(self):
        parsed = module.parse_credentials(credentials())
        self.assertEqual(parsed["key alias"], "demo")
        self.assertEqual(parsed["key store"], "suibo-release.jks")

    def test_rejects_missing_credential_fields(self):
        with self.assertRaises(ValueError):
            module.parse_credentials(b"Key alias: demo\n")

    def test_rejects_unexpected_keystore_name(self):
        with self.assertRaises(ValueError):
            module.parse_credentials(credentials().replace(
                b"suibo-release.jks", b"malicious.jks"
            ))

    def test_rejects_unexpected_zip_structure(self):
        with tempfile.TemporaryDirectory() as td:
            dest = pathlib.Path(td) / "keys.zip"
            with zipfile.ZipFile(dest, "w") as f:
                f.writestr("wrong.jks", b"not-a-real-key")
                f.writestr("signing-credentials.txt", credentials())
            with self.assertRaises(ValueError):
                module.load_private_package(dest)

    def test_valid_demo_package_only_returns_in_memory_bytes(self):
        with tempfile.TemporaryDirectory() as td:
            dest = pathlib.Path(td) / "keys.zip"
            with zipfile.ZipFile(dest, "w") as f:
                f.writestr("suibo-release.jks", b"TEST-ONLY")
                f.writestr("signing-credentials.txt", credentials())
            blob, fields = module.load_private_package(dest)
            self.assertEqual(blob, b"TEST-ONLY")
            self.assertEqual(fields["key alias"], "demo")

    def test_property_escaping_and_cert_hash(self):
        self.assertEqual(module.property_value("x\\y=z\n"), "x\\\\y\\=z\\n")
        fingerprint = "01:" * 31 + "AB"
        self.assertEqual(len(module.normalized_hash(fingerprint)), 64)
        self.assertEqual(module.checked_cert_hash(
            "Signer #1 certificate SHA-256 digest: " + ("ab" * 32),
            r"Signer #1 certificate SHA-256 digest:\s*([0-9a-f:]{64,})",
        ), "ab" * 32)


if __name__ == "__main__":
    unittest.main()
