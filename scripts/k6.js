import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
    stages: [
        { duration: '30s', target: 100 },
        { duration: '1m', target: 100 },
        { duration: '30s', target: 0 },
    ],
};


export default function () {
    // host.docker.internal is used to access the host machine from the container
    const baseUrl = 'http://host.docker.internal:8000';
    // Read from environment variable passed by Docker
    const endpoint = __ENV.ENDPOINT || '/health';

    const res = http.get(`${baseUrl}${endpoint}`);

    check(res, {
        'status is 200': (r) => r.status === 200,
        'protocol is HTTP/1.1': (r) => r.proto === 'HTTP/1.1',
    });

    sleep(1);
}
