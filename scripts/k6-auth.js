import http from 'k6/http';
import { check, sleep } from 'k6';
import { randomString } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

export const options = {
    stages: [
        { duration: '30s', target: 20 },  // Ramp to 20 VUs (realistic peak)
        { duration: '1m', target: 20 },   // Stay at 20
        { duration: '30s', target: 0 },   // Ramp down
    ],
    thresholds: {
        http_req_failed: ['rate<0.01'],
        http_req_duration: ['p(95)<2000'], // 2s is acceptable for bcrypt under load
    },
};

export default function () {
    const baseUrl = 'http://host.docker.internal:8000/api/v1';

    // Generate random user data
    const randomId = randomString(8);
    const email = `testuser_${randomId}@example.com`;
    const password = 'password123';

    const params = {
        headers: {
            'Content-Type': 'application/json',
        },
    };

    // 1. Register
    const registerPayload = JSON.stringify({
        email: email,
        password: password,
        first_name: "Test",
        last_name: "User",
        org_name: `Org ${randomId}` // Space will be normalized to hyphen by trigger
    });

    const resRegister = http.post(`${baseUrl}/auth/register`, registerPayload, params);

    // Parse once
    let regBody;
    try {
        regBody = resRegister.json();
    } catch (e) {
        regBody = {};
    }

    check(resRegister, {
        'register status is 201': (r) => {
            if (r.status !== 201) {
                console.log(`Register failed: ${r.status} ${r.body}`);
            }
            return r.status === 201;
        },
        'register has user_id': () => regBody.data && regBody.data.user_id !== undefined,
    });

    // Minimal sleep to prevent pure DoS, but allow high throughput
    sleep(0.1);

    // 2. Login
    const loginPayload = JSON.stringify({
        email: email,
        password: password,
    });

    const resLogin = http.post(`${baseUrl}/auth/login`, loginPayload, params);

    // Parse once
    let loginBody;
    try {
        loginBody = resLogin.json();
    } catch (e) {
        loginBody = {};
    }

    check(resLogin, {
        'login status is 200': (r) => r.status === 200,
        'login has access_token': () => loginBody.data && loginBody.data.access_token !== undefined,
    });

    sleep(0.1);
}
