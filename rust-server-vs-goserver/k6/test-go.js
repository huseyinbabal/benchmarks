import http from "k6/http";
import { check, sleep } from "k6";

const RUN_ID = __ENV.RUN_ID || "latest";

export const options = {
  tags: {
    run: RUN_ID,
  },
  stages: [
    { duration: "2m", target: 15000 }, // ramp up to 30k users
    { duration: "15m", target: 15000 }, // stay at 30k users for 15m
    { duration: "30s", target: 0 }, // ramp down
  ],
};

export default function () {
  const res = http.get(
    "http://hash-go.go-server-vs-rust-server.svc.cluster.local:8080/hash",
  );

  check(res, {
    "status is 200": (r) => r.status === 200,
    "has hash": (r) => JSON.parse(r.body).hash !== undefined,
    "source is go": (r) => JSON.parse(r.body).source === "go",
  });
}
