"""Errors that map to a JSON response: ``{"error": "<code>", "detail": "<message>"}``."""


class ApiError(Exception):
    status_code = 400
    code = "error"


class AuthError(ApiError):
    status_code = 401
    code = "invalid_credentials"


class NotFoundError(ApiError):
    status_code = 404
    code = "not_found"


class CardFrozenError(ApiError):
    status_code = 403
    code = "card_frozen"


class BankUnavailableError(ApiError):
    status_code = 503
    code = "bank_linking_unavailable"


class BankNotLinkedError(ApiError):
    status_code = 409
    code = "bank_not_linked"


class BankProviderError(ApiError):
    status_code = 502
    code = "bank_provider_error"
