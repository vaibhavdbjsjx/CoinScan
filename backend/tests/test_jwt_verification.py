"""
Focused test suite for JWT cryptographic verification and production security.

Tests:
1. Valid production JWT (cryptographically signed with HS256 secret)
2. Asymmetric production JWT (cryptographically signed with RS256 private key, verified with public key)
3. Invalid signature rejection in production (raises 401)
4. Expired JWT rejection in production (raises 401)
5. Malformed JWT rejection in production (raises 401)
6. Production prefix-bypass rejection (usr_, dev_, jwt_token_ raise 401 in production)
7. Non-production development-token behavior (usr_, dev_, jwt_token_ accepted in development)
8. Missing subject (sub) claim rejection in production (raises 401)
9. Missing JWT secret in production fail-closed behavior (raises 401)
"""

import time
import pytest
import jwt
from fastapi import HTTPException

from backend.app.config import settings
from backend.app.security.jwt_auth import JwtAuthVerifier, AuthenticatedUser
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization


TEST_SECRET = "coinscan-super-secret-test-key-32chars!"


@pytest.fixture(autouse=True)
def reset_settings():
    """Ensure settings are restored after each test."""
    original_env = settings.app_env
    original_secret = settings.supabase_jwt_secret
    original_pubkey = settings.supabase_jwt_public_key
    original_alg = settings.supabase_jwt_algorithm
    original_aud = settings.supabase_jwt_audience
    original_url = settings.supabase_url
    original_iss = settings.supabase_jwt_issuer

    yield

    settings.app_env = original_env
    settings.supabase_jwt_secret = original_secret
    settings.supabase_jwt_public_key = original_pubkey
    settings.supabase_jwt_algorithm = original_alg
    settings.supabase_jwt_audience = original_aud
    settings.supabase_url = original_url
    settings.supabase_jwt_issuer = original_iss


class TestJwtVerification:

    def test_valid_production_jwt_symmetric(self):
        settings.app_env = "production"
        settings.supabase_jwt_secret = TEST_SECRET
        settings.supabase_jwt_algorithm = "HS256"
        settings.supabase_jwt_audience = "authenticated"

        valid_uuid = "11111111-2222-3333-4444-555555555555"
        payload = {
            "sub": valid_uuid,
            "email": "collector@coinscan.com",
            "aud": "authenticated",
            "exp": int(time.time()) + 3600,
            "iat": int(time.time()),
        }
        token = jwt.encode(payload, TEST_SECRET, algorithm="HS256")

        verifier = JwtAuthVerifier()
        user = verifier.verify_token(token)

        assert user is not None
        assert user.user_id == valid_uuid
        assert user.email == "collector@coinscan.com"
        assert user.is_authenticated is True
        assert user.auth_method == "jwt"

    def test_valid_production_jwt_asymmetric_rs256(self):
        # Generate ephemeral RSA key pair for testing
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
        )
        pem_private = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        ).decode("utf-8")
        pem_public = private_key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        ).decode("utf-8")

        settings.app_env = "production"
        settings.supabase_jwt_public_key = pem_public
        settings.supabase_jwt_algorithm = "RS256"
        settings.supabase_jwt_audience = "authenticated"

        valid_uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        payload = {
            "sub": valid_uuid,
            "email": "rsa_user@coinscan.com",
            "aud": "authenticated",
            "exp": int(time.time()) + 3600,
            "iat": int(time.time()),
        }
        token = jwt.encode(payload, pem_private, algorithm="RS256")

        verifier = JwtAuthVerifier()
        user = verifier.verify_token(f"Bearer {token}")

        assert user is not None
        assert user.user_id == valid_uuid
        assert user.email == "rsa_user@coinscan.com"
        assert user.is_authenticated is True

    def test_non_uuid_sub_rejected_in_production(self):
        settings.app_env = "production"
        settings.supabase_jwt_secret = TEST_SECRET
        settings.supabase_jwt_algorithm = "HS256"
        settings.supabase_jwt_audience = "authenticated"

        payload = {
            "sub": "non_uuid_subject_123",
            "email": "fake@coinscan.com",
            "aud": "authenticated",
            "exp": int(time.time()) + 3600,
        }
        token = jwt.encode(payload, TEST_SECRET, algorithm="HS256")

        verifier = JwtAuthVerifier()
        with pytest.raises(HTTPException) as exc:
            verifier.verify_token(token)
        assert exc.value.status_code == 401
        assert "valid UUID in production" in exc.value.detail

    def test_invalid_signature_rejected_in_production(self):
        settings.app_env = "production"
        settings.supabase_jwt_secret = TEST_SECRET

        payload = {
            "sub": "user_forged_999",
            "email": "hacker@evil.com",
            "aud": "authenticated",
            "exp": int(time.time()) + 3600,
        }
        forged_token = jwt.encode(payload, "wrong-forged-secret-key-32chars!", algorithm="HS256")

        verifier = JwtAuthVerifier()
        with pytest.raises(HTTPException) as exc_info:
            verifier.verify_token(forged_token)
        assert exc_info.value.status_code == 401
        assert "Invalid token signature" in exc_info.value.detail

    def test_expired_jwt_rejected_in_production(self):
        settings.app_env = "production"
        settings.supabase_jwt_secret = TEST_SECRET

        payload = {
            "sub": "user_expired_001",
            "email": "expired@coinscan.com",
            "aud": "authenticated",
            "exp": int(time.time()) - 60,  # Expired 1 minute ago
        }
        expired_token = jwt.encode(payload, TEST_SECRET, algorithm="HS256")

        verifier = JwtAuthVerifier()
        with pytest.raises(HTTPException) as exc_info:
            verifier.verify_token(expired_token)
        assert exc_info.value.status_code == 401
        assert "expired" in exc_info.value.detail.lower()

    def test_malformed_jwt_rejected_in_production(self):
        settings.app_env = "production"
        settings.supabase_jwt_secret = TEST_SECRET

        verifier = JwtAuthVerifier()
        with pytest.raises(HTTPException) as exc_info:
            verifier.verify_token("header.not-a-valid-token")
        assert exc_info.value.status_code == 401

    def test_production_prefix_bypass_rejection(self):
        """Production must strictly reject prefix-based pseudo-tokens (usr_, dev_, jwt_token_)."""
        settings.app_env = "production"
        settings.supabase_jwt_secret = TEST_SECRET

        verifier = JwtAuthVerifier()

        # usr_ prefix
        with pytest.raises(HTTPException) as exc1:
            verifier.verify_token("usr_attacker123")
        assert exc1.value.status_code == 401

        # dev_ prefix
        with pytest.raises(HTTPException) as exc2:
            verifier.verify_token("dev_admin_spoof")
        assert exc2.value.status_code == 401

        # jwt_token_ prefix
        with pytest.raises(HTTPException) as exc3:
            verifier.verify_token("jwt_token_fake_bypass")
        assert exc3.value.status_code == 401

    def test_production_mock_token_rejection(self):
        """Production must not allow register_dev_user mock tokens to bypass verification."""
        settings.app_env = "production"
        settings.supabase_jwt_secret = TEST_SECRET

        verifier = JwtAuthVerifier()
        verifier.register_dev_user("mock_token_xyz", AuthenticatedUser(user_id="mock_user"))

        with pytest.raises(HTTPException) as exc:
            verifier.verify_token("mock_token_xyz")
        assert exc.value.status_code == 401

    def test_non_production_development_token_behavior(self):
        """Non-production allows prefix bypasses and registered dev users."""
        settings.app_env = "development"

        verifier = JwtAuthVerifier()

        # jwt_token_ prefix
        u1 = verifier.verify_token("jwt_token_testuser1")
        assert u1 is not None
        assert u1.user_id == "testuser1"

        # usr_ prefix
        u2 = verifier.verify_token("usr_testuser2")
        assert u2 is not None
        assert u2.user_id == "usr_testuser2"

        # dev_ prefix
        u3 = verifier.verify_token("dev_testuser3")
        assert u3 is not None
        assert u3.user_id == "dev_testuser3"

        # Registered dev user
        verifier.register_dev_user("dev_mock_key", AuthenticatedUser(user_id="custom_dev_user"))
        u4 = verifier.verify_token("dev_mock_key")
        assert u4 is not None
        assert u4.user_id == "custom_dev_user"

    def test_missing_sub_claim_in_production(self):
        settings.app_env = "production"
        settings.supabase_jwt_secret = TEST_SECRET

        payload = {
            "email": "nosub@coinscan.com",
            "aud": "authenticated",
            "exp": int(time.time()) + 3600,
        }
        token = jwt.encode(payload, TEST_SECRET, algorithm="HS256")

        verifier = JwtAuthVerifier()
        with pytest.raises(HTTPException) as exc:
            verifier.verify_token(token)
        assert exc.value.status_code == 401
        assert "subject identifier" in exc.value.detail.lower()

    def test_missing_secret_in_production_fails_closed(self):
        settings.app_env = "production"
        settings.supabase_jwt_secret = None
        settings.supabase_jwt_public_key = None

        payload = {
            "sub": "user_123",
            "aud": "authenticated",
            "exp": int(time.time()) + 3600,
        }
        token = jwt.encode(payload, "some-secret", algorithm="HS256")

        verifier = JwtAuthVerifier()
        with pytest.raises(HTTPException) as exc:
            verifier.verify_token(token)
        assert exc.value.status_code == 401

    def test_valid_issuer_accepted_in_production(self):
        settings.app_env = "production"
        settings.supabase_jwt_secret = TEST_SECRET
        settings.supabase_url = "https://xyzproject.supabase.co"

        valid_uuid = "11111111-2222-3333-4444-555555555555"
        payload = {
            "sub": valid_uuid,
            "email": "collector@coinscan.com",
            "aud": "authenticated",
            "iss": "https://xyzproject.supabase.co/auth/v1",
            "exp": int(time.time()) + 3600,
        }
        token = jwt.encode(payload, TEST_SECRET, algorithm="HS256")

        verifier = JwtAuthVerifier()
        user = verifier.verify_token(token)
        assert user is not None
        assert user.user_id == valid_uuid

    def test_mismatched_issuer_rejected_in_production(self):
        settings.app_env = "production"
        settings.supabase_jwt_secret = TEST_SECRET
        settings.supabase_url = "https://xyzproject.supabase.co"

        valid_uuid = "11111111-2222-3333-4444-555555555555"
        payload = {
            "sub": valid_uuid,
            "email": "collector@coinscan.com",
            "aud": "authenticated",
            "iss": "https://rogue-project.supabase.co/auth/v1",
            "exp": int(time.time()) + 3600,
        }
        token = jwt.encode(payload, TEST_SECRET, algorithm="HS256")

        verifier = JwtAuthVerifier()
        with pytest.raises(HTTPException) as exc:
            verifier.verify_token(token)
        assert exc.value.status_code == 401
        assert "issuer" in exc.value.detail.lower()
