package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"strconv"
	"time"
)

func Sign(secret, payload string, timestamp int64) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(strconv.FormatInt(timestamp, 10) + "." + payload))
	return hex.EncodeToString(mac.Sum(nil))
}

func Timestamp() int64 {
	return time.Now().Unix()
}
