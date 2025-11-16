"""
Clerk authentication client
"""
import jwt
from jwt import PyJWKClient
from typing import Optional, Dict
import logging
import base64

from macronome.settings import BackendConfig

logger = logging.getLogger(__name__)


class ClerkAuth:
    """Clerk JWT verification"""
    
    def __init__(self):
        self.secret_key = BackendConfig.CLERK_SECRET_KEY
        self.publishable_key = BackendConfig.CLERK_PUBLISHABLE_KEY
        
        # Log configuration on startup
        logger.info("=== Clerk Auth Configuration ===")
        logger.info(f"Publishable key present: {bool(self.publishable_key)}")
        if self.publishable_key:
            logger.info(f"Publishable key (first 20 chars): {self.publishable_key[:20]}...")
        
        # Extract instance ID from publishable key (pk_test_xxx or pk_live_xxx)
        # Format: pk_{env}_{base64_encoded_domain}
        if self.publishable_key:
            parts = self.publishable_key.split("_")
            logger.info(f"Publishable key parts: {parts}")
            
            if len(parts) >= 3:
                # The third part is base64-encoded domain
                encoded_domain = "_".join(parts[2:])
                logger.info(f"Encoded domain: {encoded_domain}")
                
                try:
                    # Add padding if needed (base64 strings must be multiples of 4)
                    padding_needed = (4 - len(encoded_domain) % 4) % 4
                    if padding_needed:
                        encoded_domain += '=' * padding_needed
                        logger.info(f"Added {padding_needed} padding chars")
                    
                    # Decode base64 to get the actual Clerk domain
                    decoded = base64.b64decode(encoded_domain).decode('utf-8')
                    # Remove trailing $ if present
                    self.instance_id = decoded.rstrip('$')
                    logger.info(f"Decoded Clerk domain: {self.instance_id}")
                except Exception as e:
                    logger.error(f"Failed to decode domain: {e}")
                    self.instance_id = None
            else:
                self.instance_id = None
                logger.error("Could not extract instance ID from publishable key")
        else:
            self.instance_id = None
            logger.error("No publishable key provided")
        
        # JWKS URL for JWT verification
        # Clerk's JWKS URL format: https://{clerk_domain}/.well-known/jwks.json
        if self.instance_id:
            self.jwks_url = f"https://{self.instance_id}/.well-known/jwks.json"
            logger.info(f"JWKS URL: {self.jwks_url}")
            
            try:
                self.jwks_client = PyJWKClient(self.jwks_url)
                logger.info("JWKS client initialized successfully")
            except Exception as e:
                logger.error(f"Failed to initialize JWKS client: {e}")
                self.jwks_client = None
        else:
            self.jwks_client = None
            logger.error("JWKS client not initialized - no instance ID")
        
        logger.info("================================")
    
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
                logger.error(f"Publishable key: {self.publishable_key[:20]}... (first 20 chars)")
                logger.error(f"Instance ID: {self.instance_id}")
                logger.error(f"JWKS URL: {self.jwks_url if self.instance_id else 'N/A'}")
                return None
            
            logger.debug(f"Verifying token (first 50 chars): {token[:50]}...")
            logger.debug(f"JWKS URL: {self.jwks_url}")
            
            # Get signing key from JWKS
            signing_key = self.jwks_client.get_signing_key_from_jwt(token)
            logger.debug("Signing key retrieved from JWKS")
            
            # Verify and decode token
            payload = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256"],
                options={"verify_exp": True}
            )
            
            logger.debug(f"Token verified successfully for user: {payload.get('sub')}")
            return payload
            
        except jwt.ExpiredSignatureError:
            logger.warning("Token expired")
            return None
        except jwt.InvalidTokenError as e:
            logger.warning(f"Invalid token: {e}")
            return None
        except Exception as e:
            logger.error(f"Error verifying token: {e}")
            logger.error(f"Error type: {type(e).__name__}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            return None


# Singleton instance
clerk_auth = ClerkAuth()

