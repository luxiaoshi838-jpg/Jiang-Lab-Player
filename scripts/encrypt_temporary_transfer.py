#!/usr/bin/env python3
"""One-way encrypted *transport only* of build output.

Only a public X.509 certificate is available to a public GitHub workflow.
Neither private signing keys nor plaintext installers enter public artifacts.
Decryption takes place off GitHub on an authorized machine.
"""
from __future__ import annotations

import argparse
import os
import struct
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

HEADER = b"SUIBOENC1"

def encrypt_file(certificate: Path, source: Path, destination: Path):
    if not source.is_file():
        raise FileNotFoundError("Build output missing")
    cert = x509.load_pem_x509_certificate(certificate.read_bytes())
    key = os.urandom(32)
    nonce = os.urandom(12)
    sealed_key = cert.public_key().encrypt(
        key,
        padding.OAEP(
            mgf=padding.MGF1(algorithm=hashes.SHA256()),
            algorithm=hashes.SHA256(),
            label=None,
        ),
    )
    if len(sealed_key) >= 65536:
        raise ValueError("Public key is unexpectedly large")
    data = source.read_bytes()
    encrypted = AESGCM(key).encrypt(nonce, data, HEADER)
    destination.write_bytes(
        HEADER + struct.pack("<H", len(sealed_key))
        + nonce + sealed_key + encrypted
    )
    print(f"Encrypted transport artifact: {destination.name}; encrypted bytes: {destination.stat().st_size}")
    print("No plaintext APK/EXE and no private key is published.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--certificate", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    encrypt_file(args.certificate, args.input, args.output)
