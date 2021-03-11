
' Copyright (c) 2019 true[X], Inc. All rights reserved.
'-----------------------------------------------------
' Utils
'-----------------------------------------------------
' Some general helper functions 
'-----------------------------------------------------

function arrayUtils_includes(array, value)
    if array = invalid then return false

    for each obj in array
        if obj = value then return true
    end for

    return false
end function