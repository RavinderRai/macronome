"""
Clerk authentication client
"""
import jwt
from jwt import PyJWKClient
from typing import Optional, Dict
import logging

from macronome.settings import BackendConfig

logger = logging.getLogger(__name__)


class ClerkAuth:
    """Clerk JWT verification"""
    
    def __init__(self):
        self.secret_key = BackendConfig.CLERK_SECRET_KEY
        self.publishable_key = BackendConfig.CLERK_PUBLISHABLE_KEY
        
        # Extract instance ID from publishable key (pk_test_xxx or pk_live_xxx)
        if self.publishable_key:
            # Format: pk_{env}_{instanceId}
            parts = self.publishable_key.split("_")
            if len(parts) >= 3:
                self.instance_id = "_".join(parts[2:])
            else:
                self.instance_id = None
        else:
            self.instance_id = None
        
        # JWKS URL for JWT verification
        if self.instance_id:
            self.jwks_url = f"https://{self.instance_id}.clerk.accounts.dev/.well-known/jwks.json"
            self.jwks_client = PyJWKClient(self.jwks_url)
        else:
            self.jwks_client = None
    
    def verify_token(self, token: str) -> Optional[Dict]:
        """
        Verify Clerk JWT token
        
        Args:
            token: JWT token from Authorization header
        
        Returns:
            Decoded token payload if valid, None otherwise
        """
        try:
            if not self.jwks_client:
                logger.error("JWKS client not initialized - check CLERK_PUBLISHABLE_KEY")
                return None
            
            # Get signing key from JWKS
            signing_key = self.jwks_client.get_signing_key_from_jwt(token)
            
            # Verify and decode token
            payload = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256"],
                options={"verify_exp": True}
            )
            
            return payload
            
        except jwt.ExpiredSignatureError:
            logger.warning("Token expired")
            return None
        except jwt.InvalidTokenError as e:
            logger.warning(f"Invalid token: {e}")
            return None
        except Exception as e:
            logger.error(f"Error verifying token: {e}")
            return None


# Singleton instance
clerk_auth = ClerkAuth()

