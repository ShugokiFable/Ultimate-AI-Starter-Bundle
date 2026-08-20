class ForgeError(RuntimeError):
    """Base Forge error."""


class ConfigurationError(ForgeError):
    pass


class ValidationError(ForgeError):
    pass


class SafetyError(ForgeError):
    pass


class ToolError(ForgeError):
    pass


class ApprovalError(SafetyError):
    pass
