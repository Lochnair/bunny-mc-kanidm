package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"errors"
	"flag"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type options struct {
	chain           string
	key             string
	cn              string
	san             string
	days            int
	renewWithinDays int
	keyType         string
	rsaBits         int
}

func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "kanidm-cert-helper: ERROR: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string, stdout *os.File) error {
	if len(args) == 0 {
		return errors.New("command is required")
	}

	switch args[0] {
	case "ensure":
		opts, err := parseOptions(args[1:])
		if err != nil {
			return err
		}
		return ensure(opts, stdout)
	case "check":
		opts, err := parseOptions(args[1:])
		if err != nil {
			return err
		}
		return check(opts, stdout)
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func parseOptions(args []string) (options, error) {
	opts := options{
		days:            3650,
		renewWithinDays: 30,
		keyType:         "ec",
		rsaBits:         2048,
	}

	fs := flag.NewFlagSet("kanidm-cert-helper", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	fs.StringVar(&opts.chain, "chain", "", "path to PEM certificate output")
	fs.StringVar(&opts.key, "key", "", "path to PEM private key output")
	fs.StringVar(&opts.cn, "cn", "", "certificate common name")
	fs.StringVar(&opts.san, "san", "", "comma-separated DNS SAN list")
	fs.IntVar(&opts.days, "days", opts.days, "validity days")
	fs.IntVar(&opts.renewWithinDays, "renew-within-days", opts.renewWithinDays, "regeneration threshold in days")
	fs.StringVar(&opts.keyType, "key-type", opts.keyType, "private key type: ec or rsa")
	fs.IntVar(&opts.rsaBits, "rsa-bits", opts.rsaBits, "RSA key size")

	if err := fs.Parse(args); err != nil {
		return opts, err
	}
	if fs.NArg() != 0 {
		return opts, fmt.Errorf("unexpected positional arguments: %s", strings.Join(fs.Args(), " "))
	}
	if opts.chain == "" {
		return opts, errors.New("--chain is required")
	}
	if opts.key == "" {
		return opts, errors.New("--key is required")
	}
	if opts.cn == "" {
		return opts, errors.New("--cn is required")
	}
	if opts.san == "" {
		opts.san = opts.cn
	}
	if opts.days <= 0 {
		return opts, errors.New("--days must be a positive integer")
	}
	if opts.renewWithinDays < 0 {
		return opts, errors.New("--renew-within-days must be a non-negative integer")
	}
	if opts.keyType != "ec" && opts.keyType != "rsa" {
		return opts, errors.New("--key-type must be one of: ec rsa")
	}
	if opts.rsaBits <= 0 {
		return opts, errors.New("--rsa-bits must be a positive integer")
	}
	if opts.keyType == "rsa" && opts.rsaBits < 2048 {
		return opts, errors.New("--rsa-bits must be at least 2048")
	}

	if _, err := parseSANs(opts.san); err != nil {
		return opts, err
	}

	return opts, nil
}

func ensure(opts options, stdout *os.File) error {
	valid, err := existingCertValid(opts)
	if err == nil && valid {
		fmt.Fprintf(stdout, "reusing existing cert at %s\n", opts.chain)
		return nil
	}
	if err != nil {
		fmt.Fprintf(stdout, "regenerating self-signed cert at %s: %v\n", opts.chain, err)
	} else {
		fmt.Fprintf(stdout, "regenerating self-signed cert at %s\n", opts.chain)
	}
	return generate(opts)
}

func check(opts options, stdout *os.File) error {
	valid, err := existingCertValid(opts)
	if err != nil {
		return err
	}
	if !valid {
		return errors.New("certificate is expired or expiring within threshold")
	}
	fmt.Fprintf(stdout, "existing cert is valid at %s\n", opts.chain)
	return nil
}

func existingCertValid(opts options) (bool, error) {
	if _, err := os.Stat(opts.chain); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, errors.New("chain file is missing")
		}
		return false, err
	}
	if _, err := os.Stat(opts.key); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, errors.New("key file is missing")
		}
		return false, err
	}

	cert, err := parseCertificateFile(opts.chain)
	if err != nil {
		return false, err
	}

	threshold := time.Now().Add(time.Duration(opts.renewWithinDays) * 24 * time.Hour)
	return cert.NotAfter.After(threshold), nil
}

func parseCertificateFile(path string) (*x509.Certificate, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	for {
		block, rest := pem.Decode(data)
		if block == nil {
			return nil, errors.New("no certificate PEM block found")
		}
		if block.Type == "CERTIFICATE" {
			return x509.ParseCertificate(block.Bytes)
		}
		data = rest
	}
}

func generate(opts options) error {
	dnsNames, err := parseSANs(opts.san)
	if err != nil {
		return err
	}

	priv, publicKey, keyUsage, err := generatePrivateKey(opts)
	if err != nil {
		return err
	}
	keyDER, err := x509.MarshalPKCS8PrivateKey(priv)
	if err != nil {
		return err
	}

	now := time.Now()
	serialLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serial, err := rand.Int(rand.Reader, serialLimit)
	if err != nil {
		return err
	}

	template := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			CommonName: opts.cn,
		},
		NotBefore:             now.Add(-5 * time.Minute),
		NotAfter:              now.Add(time.Duration(opts.days) * 24 * time.Hour),
		KeyUsage:              keyUsage,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		IsCA:                  false,
		DNSNames:              dnsNames,
	}

	certDER, err := x509.CreateCertificate(rand.Reader, template, template, publicKey, priv)
	if err != nil {
		return err
	}

	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certDER})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyDER})
	if certPEM == nil || keyPEM == nil {
		return errors.New("failed to encode PEM")
	}

	if err := os.MkdirAll(filepath.Dir(opts.chain), 0755); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(opts.key), 0755); err != nil {
		return err
	}

	if err := writeFileAtomic(opts.chain, certPEM, 0644); err != nil {
		return err
	}
	return writeFileAtomic(opts.key, keyPEM, 0600)
}

func generatePrivateKey(opts options) (priv any, publicKey any, keyUsage x509.KeyUsage, err error) {
	keyUsage = x509.KeyUsageDigitalSignature
	if opts.keyType == "rsa" {
		key, err := rsa.GenerateKey(rand.Reader, opts.rsaBits)
		if err != nil {
			return nil, nil, 0, err
		}
		return key, &key.PublicKey, keyUsage | x509.KeyUsageKeyEncipherment, nil
	}

	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, nil, 0, err
	}
	return key, &key.PublicKey, keyUsage, nil
}

func parseSANs(raw string) ([]string, error) {
	parts := strings.Split(raw, ",")
	dnsNames := make([]string, 0, len(parts))
	for _, part := range parts {
		name := strings.TrimSpace(part)
		if name == "" {
			continue
		}
		dnsNames = append(dnsNames, name)
	}
	if len(dnsNames) == 0 {
		return nil, errors.New("--san must contain at least one DNS name")
	}
	return dnsNames, nil
}

func writeFileAtomic(path string, data []byte, mode os.FileMode) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".tmp.")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	removeTmp := true
	defer func() {
		if removeTmp {
			_ = os.Remove(tmpPath)
		}
	}()

	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Chmod(mode); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpPath, path); err != nil {
		return err
	}
	removeTmp = false
	return nil
}
