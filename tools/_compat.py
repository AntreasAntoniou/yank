# StrEnum backport so ogma's trust_remote_code modules import on Python 3.10.
import enum
if not hasattr(enum, "StrEnum"):
    class StrEnum(str, enum.Enum):
        def __new__(cls, value):
            member = str.__new__(cls, value)
            member._value_ = value
            return member
        def __str__(self):
            return str(self._value_)
        @staticmethod
        def _generate_next_value_(name, start, count, last_values):
            return name.lower()
    enum.StrEnum = StrEnum
