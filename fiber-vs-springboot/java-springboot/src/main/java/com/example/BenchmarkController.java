package com.example;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.DigestException;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;

@RestController
public class BenchmarkController {

    private static final byte[] HASH_SEED = "benchmark-test-data".getBytes(StandardCharsets.UTF_8);
    private static final HexFormat HEX = HexFormat.of();

    static class ResponseDto {
        private String hash;
        private long timestamp;
        private String source;
        
        public ResponseDto(String hash, long timestamp, String source) {
            this.hash = hash;
            this.timestamp = timestamp;
            this.source = source;
        }
        
        // Getters and setters
        public String getHash() { return hash; }
        public void setHash(String hash) { this.hash = hash; }
        public long getTimestamp() { return timestamp; }
        public void setTimestamp(long timestamp) { this.timestamp = timestamp; }
        public String getSource() { return source; }
        public void setSource(String source) { this.source = source; }
    }

    @GetMapping("/hash")
    public ResponseDto hash() throws NoSuchAlgorithmException {
        // Avoid per-iteration allocations by reusing fixed-size buffers.
        MessageDigest digest = MessageDigest.getInstance("SHA-256");

        byte[] a = new byte[32];
        byte[] b = new byte[32];
        byte[] in = HASH_SEED;
        byte[] out = a;

        for (int i = 0; i < 100; i++) {
            digest.reset();
            digest.update(in);
            try {
                digest.digest(out, 0, 32);
            } catch (DigestException e) {
                throw new IllegalStateException("Unexpected digest size", e);
            }

            in = out;
            out = (out == a) ? b : a;
        }

        return new ResponseDto(
            HEX.formatHex(in),
            System.currentTimeMillis(),
            "spring-boot-4"
        );
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }
}
