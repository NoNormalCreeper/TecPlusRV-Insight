import io
import unittest

from scripts.gdb_stub_probe import RspClient, RspError, encode_packet


class FakeStream:
    def __init__(self, incoming: bytes):
        self.incoming = io.BytesIO(incoming)
        self.written = bytearray()

    def read(self, size: int) -> bytes:
        return self.incoming.read(size)

    def write(self, data: bytes) -> int:
        self.written.extend(data)
        return len(data)

    def flush(self) -> None:
        pass


class RspClientTest(unittest.TestCase):
    def test_stop_reason_round_trip(self):
        stream = FakeStream(b"+$S05#b8")
        client = RspClient(stream)

        self.assertEqual(client.exchange("?"), "S05")
        self.assertEqual(stream.written, b"$?#3f+")

    def test_target_nack_retries_request(self):
        stream = FakeStream(b"-+$OK#9a")
        client = RspClient(stream)

        self.assertEqual(client.exchange("Hg0"), "OK")
        request = encode_packet("Hg0")
        self.assertEqual(stream.written, request + request + b"+")

    def test_empty_reply_is_supported(self):
        stream = FakeStream(b"+$#00")
        client = RspClient(stream)

        self.assertEqual(client.exchange("vMustReplyEmpty"), "")

    def test_bad_reply_checksum_is_rejected(self):
        stream = FakeStream(b"+$S05#00")
        client = RspClient(stream)

        with self.assertRaisesRegex(RspError, "checksum"):
            client.exchange("?")
        self.assertTrue(stream.written.endswith(b"-"))

    def test_register_reply_keeps_all_264_hex_chars(self):
        payload = "0" * 264
        stream = FakeStream(b"+" + encode_packet(payload))
        client = RspClient(stream)

        self.assertEqual(client.exchange("g"), payload)


if __name__ == "__main__":
    unittest.main()
