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
_handle_args()
{
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
    # Output:
    # function_index

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
            derived_flag_name=$(get_long_flag_var_name "${valid_long_option[$i]}")
            derived_flag_name="${derived_flag_name}_flag"
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

    non_flagged_args=()
    # While there are input arguments left
    while [[ -n "$1" ]]
    do
        is_long_flag "$1"; is_long_flag_exit_code=$?

        if (( $is_long_flag_exit_code == 3 ))
        then
            # TODO: Update such that '-' can be used in the flag name
            define error_info << END_OF_ERROR_INFO
Given long flag have invalid format, cannot create variable name from it: '$1'
END_OF_ERROR_INFO

            define function_usage_register_function_flags << END_OF_FUNCTION_USAGE
Registered flags through register_function_flags() must follow the valid_var_name() validation.
END_OF_FUNCTION_USAGE

            # TODO: Replace with more general error
            invalid_function_usage 0 "$function_usage_register_function_flags" "$error_info"
            exit 1
        fi

        if ! is_short_flag "$1" && (( is_long_flag_exit_code != 0))
        then
            # Not a flag
            non_flagged_args+=("$1")
            shift
            continue
        fi

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
                    derived_flag_name=$(get_long_flag_var_name "${valid_long_option[$i]}")
                    derived_flag_name="${derived_flag_name}_flag"
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
Option ${valid_short_options[$i]} and ${valid_long_option[$i]} expects a value supplied after it."
END_OF_ERROR_INFO
                        invalid_function_usage 1 "$function_usage" "$error_info"
                        exit 1
                    fi

                    # Store given value after flag
                    declare -g "${derived_flag_name}_value"="$1"
                fi

                was_option_handled='true'
                break
            fi
        done

        if [[ "$was_option_handled" != 'true' ]]
        then
            define error_info <<END_OF_ERROR_INFO
Given flag '$1' is not registered for function id: '$function_id'
END_OF_ERROR_INFO
            invalid_function_usage 1 "$function_usage" "$error_info"
            exit 1
        fi

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

    if [[ -z "$function_id" ]]
    then
        define error_info <<END_OF_ERROR_INFO
Given <function_id> is empty.
END_OF_ERROR_INFO
        invalid_function_usage 2 "$function_usage" "$error_info"
        exit 1
    fi

    # Check if function id already registered
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

    local short_option=()
    local long_option=()
    local expect_value=()
    while (( $# > 1 ))
    do
        local input_short_flag="$1"
        local input_long_flag="$2"
        local input_expect_value="$3"

        if [[ -z "$input_short_flag" ]] && [[ -z "$input_long_flag"  ]]
        then
            define error_info <<END_OF_ERROR_INFO
Neither short or long flag were given for <function_id>: '$function_id'
END_OF_ERROR_INFO
            invalid_function_usage 1 "$function_usage" "$error_info"
            exit 1
        fi

        if ! is_short_flag "$input_short_flag"
        then
            local flag_exit_code=$?

            case $flag_exit_code in
                1)  ;; # Input flag empty
                2)
                    define error_info <<END_OF_ERROR_INFO
Invalid short flag format: '$input_short_flag'
Must start with a single hyphen '-'
END_OF_ERROR_INFO
                    invalid_function_usage 2 "$function_usage" "$error_info"
                    exit 1
                    ;;
                3)
                    define error_info <<END_OF_ERROR_INFO
Invalid short flag format: '$input_short_flag'
Must have exactly a single letter after the hyphen '-'
END_OF_ERROR_INFO
                    invalid_function_usage 2 "$function_usage" "$error_info"
                    exit 1
                    ;;
                *)  ;;
            esac
        fi

        # Validate long flag format, if not empty
        if ! is_long_flag "$input_long_flag"
        then
            local flag_exit_code=$?
            
            case $flag_exit_code in
                1)  ;; # Input flag empty
                2)
                    define error_info <<END_OF_ERROR_INFO
Invalid long flag format: '$input_long_flag'
Must start with double hyphen '--'
END_OF_ERROR_INFO
                    invalid_function_usage 2 "$function_usage" "$error_info"
                    exit 1
                    ;;
                3)
                    define error_info <<END_OF_ERROR_INFO
Invalid long flag format: '$input_long_flag'
Characters after '--' must start with a letter or underscore and can only
contain letters, numbers and underscores thereafter.
END_OF_ERROR_INFO
                    invalid_function_usage 2 "$function_usage" "$error_info"
                    exit 1
                    ;;
                *)  ;;
            esac
        fi

        # Check if 'input_expect_value' was given
        if [[ "$input_expect_value" != 'true' && "$input_expect_value" != 'false' ]]
        then
            define error_info << END_OF_ERROR_INFO
Invalid 'expect_value': '$input_expect_value'
Must have the value of 'true' or 'false'.
END_OF_ERROR_INFO
            invalid_function_usage 1 "$function_usage" "$error_info"
            exit 1
        fi

        [[ -z "$input_short_flag" ]] && short_option+=("_") || short_option+=("$1")
        [[ -z "$input_long_flag" ]] && long_option+=("_") || long_option+=("$2")
        [[ -z "$input_expect_value" ]] && expect_value+=("_") || expect_value+=("$3")

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

is_short_flag()
{
    local to_check="$1"

    [[ -z "$to_check" ]] && return 1

    # Check that it starts with a single hyphen, not double
    [[ "$to_check" =~ ^-[^-] ]] || return 2

    # Check that it has a single character after the hypen
    [[ "$to_check" =~ ^-[[:alpha:]]$ ]] || return 3

    return 0
}

is_long_flag()
{
    local to_check="$1"

    [[ -z "$to_check" ]] && return 1

    [[ "$to_check" =~ ^-- ]] || return 2

    # TODO: Update such that we cannot have the long flags '--_', '--__'
    #       etc.
    get_long_flag_var_name "$to_check" &>/dev/null || return 3

    return 0
}

# Outputs valid variable name if the flag is valid, replaces hyphen with underscore
get_long_flag_var_name()
{
    local long_flag="${1#--}" # Remove initial --

    grep -q '^[[:alpha:]][-[:alpha:][:digit:]]*$' <<< "$long_flag" || return 1

    # Replace hyphens with underscore
    local var_name=$(sed 's/-/_/g' <<< "$long_flag")

    valid_var_name "$var_name" || return 1

    echo "$var_name"
}

valid_var_name() {
    grep -q '^[_[:alpha:]][_[:alpha:][:digit:]]*$' <<< "$1"
}
