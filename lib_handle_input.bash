#####################
### Guard library ###
#####################
guard_source_max_once() {
    local file_name="$(basename "${BASH_SOURCE[0]}")"
    local guard_var="guard_${file_name%.*}" # file_name wo file extension

    [[ "${!guard_var}" ]] && return 1
    [[ "$guard_var" =~ ^[_a-zA-Z][_a-zA-Z0-9]*$ ]] \
        || { echo "Invalid guard: '$guard_var'"; exit 1; }
    declare -gr "$guard_var=true"
}

guard_source_max_once || return

##############################
### Library initialization ###
##############################
init_lib()
{
    # Unset as only called once and most likely overwritten when sourcing libs
    unset -f init_lib

    if ! [[ -d "$LIB_PATH" ]]
    then
        echo "LIB_PATH is not defined to a directory for the sourced script."
        echo "LIB_PATH: '$LIB_PATH'"
        exit 1
    fi

    ### Source libraries ###
    #
    # Always start with 'lib_core.bash'
    source "$LIB_PATH/lib_core.bash"
}

init_lib

#####################
### Library start ###
#####################

# Process flags & non-optional arguments
_handle_args() {
    local function_id="$1"
    shift

    define function_usage <<'END_OF_FUNCTION_USAGE'
Usage: _handle_args <function_id> "$@"
    <function_id>:
        * Each function can have its own set of flags. The function id is used
          for identifying which flags to parse and how to parse them.
            - Function id can e.g. be the function name.
        * Should be registered through register_function_flags() before calling
          this function
END_OF_FUNCTION_USAGE

    _validate_input_handle_args

    # Convert space separated elements into an array
    IFS=' ' read -ra valid_short_options <<< "${_handle_args_registered_function_short_option[$function_index]}"
    IFS=' ' read -ra valid_long_option <<< "${_handle_args_registered_function_long_option[$function_index]}"
    IFS=' ' read -ra expects_value <<< "${_handle_args_registered_function_values[$function_index]}"

    # Declare and initialize output variables
    # <long/short option>_flag = 'false'
    # <long/short option>_flag_value = ''
    for i in "${!valid_short_options[@]}"
    do
        local derived_flag_name=""
        
        # Find out variable naming prefix
        # Prefer the long option name if it exists
        if [[ "${valid_long_option[$i]}" != "_" ]]
        then
            derived_flag_name="${valid_long_option[$i]#--}_flag"
        else
            derived_flag_name="${valid_short_options[$i]#-}_flag"
        fi

        # Initialization
        declare -g "$derived_flag_name"='false'
        if [[ "${expects_value[$i]}" == "true" ]]
        then
            declare -g "${derived_flag_name}_value"=''
        fi
    done

    # While there are input arguments left
    while [[ -n "$1" ]]
    do
        local was_option_handled='false'

        for i in "${!valid_short_options[@]}"
        do
            local derived_flag_name=""
            if [[ "$1" == "${valid_long_option[$i]}" ]] || [[ "$1" == "${valid_short_options[$i]}" ]]
            then
                
                # Find out variable naming prefix
                # Prefer the long option name if it exists
                if [[ "${valid_long_option[$i]}" != "_" ]]
                then
                    derived_flag_name="${valid_long_option[$i]#--}_flag"
                else
                    derived_flag_name="${valid_short_options[$i]#-}_flag"
                fi

                # Indicate that flag was given
                declare -g "$derived_flag_name"='true'

                if [[ "${expects_value[$i]}" == 'true' ]]
                then
                    shift

                    local first_character_hyphen='false'
                    [[ "${1:0:1}" == "-" ]] && first_character_hyphen='true'

                    if [[ -z "$1" ]] || [[ "$first_character_hyphen" == 'true' ]]
                    then
                        define error_info <<END_OF_ERROR_INFO
Option ${valid_short_options[$i]} and ${valid_long_option[$i]}) expects a value supplied after it."
END_OF_ERROR_INFO
                        invalid_function_usage 1 "$function_usage" "$valid_long_option"
                        exit 1
                    fi

                    # Store given value after flag
                    declare -g "${derived_flag_name}_value"="$1"
                fi

                was_option_handled='true'
                break
            fi
        done

        [[ "$was_option_handled" == 'false' ]] && non_flagged_args+=("$1")

        shift
    done
}

_validate_input_handle_args()
{
    if [[ -z "$function_id" ]]
    then
        define error_info <<'END_OF_ERROR_INFO'
Given <function_id> is empty.
END_OF_ERROR_INFO
        invalid_function_usage 2 "$function_usage" "$error_info"
        exit 1
    fi

    # Check that <function_id> is registered through register_function_flags()
    local function_registered='false'
    local function_index
    for i in "${!_handle_args_registered_function_ids[@]}"
    do
        if [[ "${_handle_args_registered_function_ids[$i]}" == "$function_id" ]]
        then
            function_registered='true'
            function_index=$i
            break
        fi
    done

    if [[ "$function_registered" != 'true' ]]
    then
        define error_info <<END_OF_ERROR_INFO
Given <function_id> is not registered through register_function_flags() before
calling _handle_args(). <function_id>: '$function_id'
END_OF_ERROR_INFO
        invalid_function_usage 2 "$function_usage" "$error_info"
        exit 1
    fi
}

# Arrays to store _handle_args() data
_handle_args_registered_function_ids=()
_handle_args_registered_function_short_option=()
_handle_args_registered_function_long_option=()
_handle_args_registered_function_values=()

# Register valid flags for a function
register_function_flags() {
    local function_id="$1"
    shift

    define function_usage <<END_OF_FUNCTION_USAGE
Usage: register_function_flags <function_id> \
                               <short_flag_1> <long_flag_1> <expect_value_1> \
                               <short_flag_2> <long_flag_2> <expect_value_2> \
                               ...
    Registers how many function flags as you want, always in a set of 3 input
    arguments: <short_flag> <long_flag> <expect_value>
    
    Either of <short_flag> or <long_flag> can be empty, but must then be entered
    as an empty string "".

    <function_id>:
        * Each function can have its own set of flags. The function id is used
          for identifying which flags to parse and how to parse them.
            - Function id can e.g. be the function name.
    <short_flag_#>:
        * Single dash flag.
        * E.g. '-e'
    <long_flag_#>:
        * Double dash flag
        * E.g. '--echo'
    <expect_value_#>:
        * String boolean which indicates if an associated value is expected
          after the flag.
        * 'true' = There shall be a value supplied after the flag
END_OF_FUNCTION_USAGE

    _validate_input_register_function_flags

    local short_option=()
    local long_option=()
    local expect_value=()
    while (( $# > 1 ))
    do

        if [[ -z "$1" ]] && [[ -z "$2"  ]]
        then
            define error_info <<END_OF_ERROR_INFO
Neither short or long flag were given for <function_id>: '$function_id'
END_OF_ERROR_INFO
            invalid_function_usage 1 "$function_usage" "$error_info"
            exit 1
        fi

        [[ -z "$1" ]] && short_option+=("_") || short_option+=("$1")
        [[ -z "$2" ]] && long_option+=("_") || long_option+=("$2")
        [[ -z "$3" ]] && expect_value+=("_") || expect_value+=("$3")

        shift 3  # Move past option, long option, and value expectation
    done

    ### Append to global arrays
    #
    # [*] used to save all space separated at the same index, to map all options
    # to the same registered function name
    _handle_args_registered_function_ids+=("$function_id")
    _handle_args_registered_function_short_option+=("${short_option[*]}")
    _handle_args_registered_function_long_option+=("${long_option[*]}")
    _handle_args_registered_function_values+=("${expect_value[*]}")
}

_validate_input_register_function_flags()
{
    if [[ -z "$function_id" ]]
    then
        define error_info <<END_OF_ERROR_INFO
Given <function_id> is empty.
END_OF_ERROR_INFO
        invalid_function_usage 2 "$function_usage" "$error_info"
        exit 1
    fi

    for registered in "${_handle_args_registered_function_ids[@]}"
    do
        if [[ "$function_id" == "$registered" ]]
        then
            define error_info <<END_OF_ERROR_INFO
Given <function_id> is already registered: '$function_id'
END_OF_ERROR_INFO
            invalid_function_usage 2 "$function_usage" "$error_info"
            exit 1
        fi
    done
}

# Used for handling arrays as function parameters
# Creates dynamic arrays from the input
# 1: Dynamic array name prefix e.g. 'input_arr'
#    Creates dynamic arrays 'input_arr1', 'input_arr2', ...
# 2: Length of array e.g. "${#arr[@]}"
# 3: Array content e.g. "${arr[@]}"
# 4: Length of the next array
# 5: Content of the next array
# 6: ...
handle_input_arrays_dynamically()
{
    local dynamic_array_prefix="$1"; shift
    local array_suffix=1

    local is_number_regex='^[0-9]+$'

    while (( $# )) ; do
        local num_array_elements=$1; shift

        if ! [[ "$num_array_elements" =~ $is_number_regex ]]
        then
            echo "Given number of array elements is not a number: $num_array_elements"
            exit 1
        fi
        
        eval "$dynamic_array_prefix$array_suffix=()";
        while (( num_array_elements-- > 0 )) 
        do

            if ((num_array_elements == 0)) && ! [[ "${1+nonexistent}" ]]
            then
                # Last element is not set
                echo "Given array contains less elements than the explicit array size given."
                exit 1
            fi
            eval "$dynamic_array_prefix$array_suffix+=(\"\$1\")"; shift
        done
        ((array_suffix++))
    done
}
