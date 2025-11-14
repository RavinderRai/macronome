import os
from macronome.settings import BackendConfig
"""
Database Utility Module

This module provides utility functions for database operations.
It includes methods for retrieving connection strings and managing database sessions.
"""

class DatabaseUtils:
    @staticmethod
    def get_connection_string():
        db_host = BackendConfig.DB_HOST
        db_port = BackendConfig.DB_PORT
        db_name = BackendConfig.DB_NAME
        db_user = BackendConfig.DB_USER
        db_password = BackendConfig.DB_PASSWORD
        return f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"