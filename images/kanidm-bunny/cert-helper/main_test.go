package main

import (
	"crypto/x509"
	"encoding/pem"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func TestEnsureGeneratesMissingFiles(t *testing.T) {
	opts := testOptions(t, "ec", 3650, 30)

	if err := ensure(opts, os.Stdout); err != nil {
		t.Fatalf("ensure failed: %v", err)
	}

	cert := readCert(t, opts.chain)
	if cert.Subject.CommonName != opts.cn {
		t.Fatalf("CommonName = %q, want %q", cert.Subject.CommonName, opts.cn)
	}
	if !contains(cert.DNSNames, "idm.svee.eu") || !contains(cert.DNSNames, "login.svee.eu") {
		t.Fatalf("DNSNames = %#v, want idm.svee.eu and login.svee.eu", cert.DNSNames)
	}
	assertMode(t, opts.chain, 0644)
	assertMode(t, opts.key, 0600)
}

func TestEnsureReusesNonExpiringCert(t *testing.T) {
	opts := testOptions(t, "ec", 3650, 30)
	if err := ensure(opts, os.Stdout); err != nil {
		t.Fatalf("first ensure failed: %v", err)
	}
	first := readFile(t, opts.chain)

	if err := ensure(opts, os.Stdout); err != nil {
		t.Fatalf("second ensure failed: %v", err)
	}
	second := readFile(t, opts.chain)

	if string(first) != string(second) {
		t.Fatal("second ensure regenerated a non-expiring certificate")
	}
}

func TestEnsureRegeneratesInvalidCert(t *testing.T) {
	opts := testOptions(t, "ec", 3650, 30)
	if err := os.MkdirAll(filepath.Dir(opts.chain), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(opts.chain, []byte("not a certificate\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(opts.key, []byte("not a key\n"), 0600); err != nil {
		t.Fatal(err)
	}

	if err := ensure(opts, os.Stdout); err != nil {
		t.Fatalf("ensure failed: %v", err)
	}
	readCert(t, opts.chain)
}

func TestEnsureRegeneratesNearExpiryCert(t *testing.T) {
	opts := testOptions(t, "ec", 1, 30)
	if err := ensure(opts, os.Stdout); err != nil {
		t.Fatalf("first ensure failed: %v", err)
	}
	first := readFile(t, opts.chain)

	opts.days = 3650
	if err := ensure(opts, os.Stdout); err != nil {
		t.Fatalf("second ensure failed: %v", err)
	}
	second := readFile(t, opts.chain)

	if string(first) == string(second) {
		t.Fatal("near-expiry certificate was reused")
	}
	if !readCert(t, opts.chain).NotAfter.After(time.Now().Add(30 * 24 * time.Hour)) {
		t.Fatal("regenerated certificate is still near expiry")
	}
}

func TestEnsureGeneratesRSAAndECKeys(t *testing.T) {
	for _, keyType := range []string{"ec", "rsa"} {
		t.Run(keyType, func(t *testing.T) {
			opts := testOptions(t, keyType, 3650, 30)
			if err := ensure(opts, os.Stdout); err != nil {
				t.Fatalf("ensure failed: %v", err)
			}
			cert := readCert(t, opts.chain)
			switch keyType {
			case "ec":
				if cert.PublicKeyAlgorithm != x509.ECDSA {
					t.Fatalf("PublicKeyAlgorithm = %v, want ECDSA", cert.PublicKeyAlgorithm)
				}
			case "rsa":
				if cert.PublicKeyAlgorithm != x509.RSA {
					t.Fatalf("PublicKeyAlgorithm = %v, want RSA", cert.PublicKeyAlgorithm)
				}
			}
		})
	}
}

func testOptions(t *testing.T, keyType string, days int, renewWithinDays int) options {
	t.Helper()
	dir := t.TempDir()
	return options{
		chain:           filepath.Join(dir, "tls", "chain.pem"),
		key:             filepath.Join(dir, "tls", "key.pem"),
		cn:              "idm.svee.eu",
		san:             "idm.svee.eu,login.svee.eu",
		days:            days,
		renewWithinDays: renewWithinDays,
		keyType:         keyType,
		rsaBits:         2048,
	}
}

func readCert(t *testing.T, path string) *x509.Certificate {
	t.Helper()
	data := readFile(t, path)
	block, _ := pem.Decode(data)
	if block == nil || block.Type != "CERTIFICATE" {
		t.Fatalf("no certificate PEM in %s", path)
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatalf("parse cert: %v", err)
	}
	return cert
}

func readFile(t *testing.T, path string) []byte {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func assertMode(t *testing.T, path string, want os.FileMode) {
	t.Helper()
	if runtime.GOOS == "windows" {
		return
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != want {
		t.Fatalf("%s mode = %o, want %o", path, got, want)
	}
}

func contains(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}
