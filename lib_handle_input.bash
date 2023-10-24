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

    if [[ -z "$function_id" ]]
    then
        echo "ERROR: Given <function_id> is empty."
        exit 1
    fi

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
        echo "ERROR: Function is not registered: '$function_id'"
        exit 1
    fi

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
                        echo "Error: Option ${valid_short_options[$i]} (or ${valid_long_option[$i]}) expects a value"
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

# Arrays to store _handle_args() data
_handle_args_registered_function_ids=()
_handle_args_registered_function_short_option=()
_handle_args_registered_function_long_option=()
_handle_args_registered_function_values=()

# Register valid flags for a function
register_function_flags() {
    local function_id="$1"
    shift 

    if [[ -z "$function_id" ]]
    then
        echo "ERROR: Function name is empty"
        exit 1
    fi

    for registered in "${_handle_args_registered_function_ids[@]}"
    do
        if [[ "$function_id" == "$registered" ]]
        then
            echo "ERROR: Function name already registered: '$function_id'"
            exit 1
        fi
    done

    local short_option=()
    local long_option=()
    local expect_value=()
    while (( $# > 1 ))
    do

        if [[ -z "$1" ]] && [[ -z "$2"  ]]
        then
            echo "ERROR: Neither short or long option given for '$function_id'."
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
