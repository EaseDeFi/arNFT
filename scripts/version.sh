# linux
#EXP="s/pragma solidity.*/pragma solidity $@;/g"
#find ./contracts/ \( -type d -name .git -prune \) -o -type f -print0 | xargs -0 sed -i "$EXP"
# mac os
EXP="s/pragma solidity.*/pragma solidity $@;/g"
find contracts/ \( -type d -name .git -prune \) -o -type f -print0 | xargs -0 sed -i '' "$EXP"
