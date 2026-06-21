package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/mcweb/mcweb-hostd/internal/config"
)

const (
	cookieName   = "mcweb_hostd_session"
	sessionTTL   = 24 * time.Hour
	csrfField    = "csrf_token"
	csrfCookie   = "mcweb_hostd_csrf"
)

type Session struct {
	Username  string
	ExpiresAt time.Time
}

type Manager struct {
	cfg *config.Config
}

func New(cfg *config.Config) *Manager {
	return &Manager{cfg: cfg}
}

func (m *Manager) SignSession(username string) (string, error) {
	if m.cfg.SecretKey == "" {
		return "", errors.New("secret key not configured")
	}
	exp := time.Now().Add(sessionTTL).Unix()
	payload := username + "|" + time.Unix(exp, 0).Format(time.RFC3339)
	mac := hmac.New(sha256.New, []byte(m.cfg.SecretKey))
	mac.Write([]byte(payload))
	sig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return base64.RawURLEncoding.EncodeToString([]byte(payload)) + "." + sig, nil
}

func (m *Manager) VerifySession(token string) (string, bool) {
	if token == "" || m.cfg.SecretKey == "" {
		return "", false
	}
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return "", false
	}
	payloadBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return "", false
	}
	payload := string(payloadBytes)
	mac := hmac.New(sha256.New, []byte(m.cfg.SecretKey))
	mac.Write([]byte(payload))
	expected := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(expected), []byte(parts[1])) {
		return "", false
	}
	segments := strings.Split(payload, "|")
	if len(segments) != 2 {
		return "", false
	}
	exp, err := time.Parse(time.RFC3339, segments[1])
	if err != nil || time.Now().After(exp) {
		return "", false
	}
	return segments[0], true
}

func (m *Manager) SetSessionCookie(w http.ResponseWriter, r *http.Request, username string) error {
	token, err := m.SignSession(username)
	if err != nil {
		return err
	}
	http.SetCookie(w, &http.Cookie{
		Name:     cookieName,
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		Secure:   requestIsSecure(r),
		SameSite: http.SameSiteLaxMode,
		MaxAge:   int(sessionTTL.Seconds()),
	})
	return nil
}

func (m *Manager) ClearSession(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{Name: cookieName, Value: "", Path: "/", MaxAge: -1})
}

func (m *Manager) UsernameFromRequest(r *http.Request) (string, bool) {
	c, err := r.Cookie(cookieName)
	if err != nil {
		return "", false
	}
	return m.VerifySession(c.Value)
}

func (m *Manager) NewCSRF() string {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		panic(err)
	}
	return base64.RawURLEncoding.EncodeToString(buf)
}

func (m *Manager) SetCSRFCookie(w http.ResponseWriter, r *http.Request, token string) {
	http.SetCookie(w, &http.Cookie{
		Name:     csrfCookie,
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		Secure:   requestIsSecure(r),
		SameSite: http.SameSiteStrictMode,
	})
}

func requestIsSecure(r *http.Request) bool {
	if r.TLS != nil {
		return true
	}
	return strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https")
}

func (m *Manager) ValidateCSRF(r *http.Request) bool {
	form := r.FormValue(csrfField)
	c, err := r.Cookie(csrfCookie)
	if err != nil || form == "" {
		return false
	}
	return hmac.Equal([]byte(form), []byte(c.Value))
}

func CSRFTokenField() string { return csrfField }
