# Sample production source file with a qi-trace marker.
# qi-trace: AB#1002

def login(user, password):
    return user is not None and password is not None
