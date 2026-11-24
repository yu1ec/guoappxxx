package core

import (
	"crypto/tls"
	"crypto/x509"
	"errors"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"testing"
)

// Use the production wrapper shape, without issuing any provider request or
// reading front-end scripts. Android cannot rely on Go loading system roots.
func yeguoProductionTLSClient() *http.Client {
	d := &Downloader{client: &http.Client{Transport: &huangguoBrowserTransport{}}}
	return (&yeguoAPIClient{downloader: d}).requestClient()
}

func TestYeguoRequestClientIncludesBundledRoots(t *testing.T) {
	client := yeguoProductionTLSClient()
	transport, ok := client.Transport.(*http.Transport)
	if !ok || transport.TLSClientConfig == nil {
		t.Fatal("missing standard TLS transport")
	}
	config := transport.TLSClientConfig
	if config.RootCAs == nil {
		t.Fatal("Yeguo API transport drops bundled CA roots required by Android")
	}
	if config.InsecureSkipVerify || config.MinVersion < tls.VersionTLS12 {
		t.Fatal("TLS verification or minimum version weakened")
	}
	bundled := x509.NewCertPool()
	if !bundled.AppendCertsFromPEM(embeddedCACerts) {
		t.Fatal("missing embedded public CA bundle")
	}
	actual := map[string]bool{}
	for _, subject := range config.RootCAs.Subjects() {
		actual[string(subject)] = true
	}
	for _, subject := range bundled.Subjects() {
		if !actual[string(subject)] {
			t.Fatal("API transport omitted a bundled public CA")
		}
	}
}

func TestYeguoRequestClientStillRejectsUntrustedCertificate(t *testing.T) {
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.WriteString(w, "synthetic fixture")
	}))
	server.Config.ErrorLog = log.New(io.Discard, "", 0)
	server.StartTLS()
	defer server.Close()
	client := yeguoProductionTLSClient()
	response, err := client.Get(server.URL)
	if response != nil {
		response.Body.Close()
	}
	var unknown x509.UnknownAuthorityError
	if err == nil || !errors.As(err, &unknown) {
		t.Fatalf("untrusted TLS certificate was not rejected: %v", err)
	}
}
