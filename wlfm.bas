#include "vbcompat.bi" ' Needed for:
'now
#include "file.bi" ' Needed for:
'filelen
'filexists
'truncate

'Warlords does support EGA and VGA. So on the worst machine used for the game,
'EGA chould be the case, which translates to mode 9:
screen 9
'But that allows for 43 lines!
width 80, 43
'We don't need no stinkin' mouse pointer...
setmouse -1, -1, 0
'====== Constants ======
'==== General Technical Constants ====
const version as string = "1.0"
'== Some Consistent Error Codes Used Throughout the Application
const open_error as ubyte = 1
const write_error as ubyte = 2
const read_error as ubyte = 3
const deletion_error as ubyte = 4
const truncate_error as ubyte = 5
const not_warlords_folder as ubyte = 6
const coding_error as ubyte = 255
'== Some Flags For Debugging ==
const debug as ubyte = 0
const force_init as ubyte = 0
'==== Actual Program Constants and Types ====
'Concept for the save blob:
'Sorted list of records consisting of three values, the start and the end of a
'file record as well as a deleted flag.
'A file record can have variable size, but has a fixed size header.
'Header precedes the actual file contents, which are the variable size part. The
'header itself consists of a description of the file with up to 46 characters,
'a checksum and a time stamp when it was added.
'This just fits in the list of saved games from the manager:
const description_max_size as ubyte = 46 
type reference_record field = 1 '         all in all      78 Bytes
    start as uinteger           ' 32 bits under DOS,       4 Bytes
    end_ as uinteger            ' 32 bits under DOS,       4 Bytes
    deleted as ubyte            '  8 bits,                 1 Byte
    check_sum as ulong          ' 32 bits,                 4 Bytes
    time_stamp as double        ' 64 bits,                 8 bytes
                                '352 bits, but in reality 45 Bytes:
    description as string * description_max_size
end type
const boundary_error_flag as ubyte = 1
const check_sum_error_flag as ubyte = 2
const sort_error_flag = 4
'This is the big reference list. We will not push that around as a variable...
dim shared references() as reference_record
'Sounds rather generous, but I dunno yet, if this could be less or more.
'Just know, that check_manager_integrity() may need other data types than ubyte,
'if you increase this here.
const max_ref_records as ubyte = 128
'4 Lines may be added by certain prints (e.g. headings). And we need one empty
'line at the end, for the final print (locate must work). Even the most limited
'graphics modes have at least 25 lines per screen. So, 20 records per page
'should work always. Leaves some space for printing messages. The 640x350 screen
'mode 9 has 43 rows, so 38 should be OK.
const records_per_page as ubyte = 38
'128 reference records each 78 bytes makes 9984 bytes for the index
'and offsets are 1-based
const data_start_offset as uinteger = _
    max_ref_records * sizeof(reference_record) + 1
'Data Offset is always > 0, so this guy here can be used to indicate, that
'basically the saves file is full. Not for no disk space, but all reference
'slots in use...
const references_full_offset as ubyte = 0
const ref_block_size as ubyte = sizeof(reference_record)
const saves_file_name as string = "wars.sav"

'These are special indizes for the reference table.
'The must always be defined to be > max_ref_records or < 1!
const references_depleted = 255
const references_empty = 0
const references_table_full = 255
const reference_missing = 255
const reference_deleted = 254

'Each Warlords save is one of 8 physical files, WAR1.SAV to WAR8.SAV. None of
'them are required to exist, but any one of them can.
type wl_save_file
    exists as ubyte
    name as string
    '32 bits seems excessive, but betting on less than 64 kB is actually risky:
    size as uinteger
end type
'====== Functions Area ======
'==== Very Basic Stuff ====
'== Some Debugging Stuff
sub debug_print_line(text as string)
    if debug = 0 then return
    print text
end sub

sub debug_print(text as string)
    if debug = 0 then return
    print text;
end sub

sub wait_for_enter (a as string)
    dim dummy as string
    print a;
    dim code as long = 0
    while code <> 13 and not (debug = 1 and code = 27)
        code = getkey
    wend
    if (debug and code = 27) then
        print "Debug Exit!"
        system coding_error
    end if
end sub

sub wait_for_esc (a as string)
    print a
    dim code as long = 0
    while code <> 27
        code = getkey
    wend
end sub

'==== Some Error Handlers ====
'It is really tedious to write this over and over...
sub handle_open_error (error_code as long, _
                       file_name as string, _
                       access_type as string)
    if error_code <> 0 then
        wait_for_enter("Could not open " + file_name + " for " + access_type + _
                       " access: " + str(error_code))
        system open_error
    end if
end sub

sub handle_write_error (error_code as long, file_name as string)
    if error_code <> 0 then
        if error_code = 3 then
            wait_for_enter("Disk full. Could not write to " + file_name)
        else
            wait_for_enter("Unknown error while writing to file " + file_name _
                           + ": " + str(error_code))
        end if
        system write_error
    end if
end sub

sub handle_read_error (error_code as long, _
                       file_handle as long, _
                       file_name as string)
    if error_code = 0 then return
    if eof(file_handle) then
        print "Reached end of file for file " + file_name + ". Faulty file?"
        wait_for_enter("")
        system read_error
    end if
end sub

sub handle_deletion_error (error_code as long, file_name as string)
    if error_code = 0 then return
    wait_for_enter("Could not delete file " + file_name + ".")
    system deletion_error
end sub

sub handle_truncate_error (error_code as long, file_name as string)
    if error_code = 0 then return
    wait_for_enter("Could not delete file " + file_name + ".")
    system truncate_error
end sub

sub handle_coding_error (error_message as string)
    print error_message
    wait_for_enter("")
    system coding_error
end sub

'== Text And User Input Handling ==
'Have I ever mentioned how much I hate Pascal strings? It's so fucking 1965, it
'hurts. They could have done that better even back then... But they didn't.
function get_qb_string_from_pascal_string (p_string() as ubyte) as string
    dim lower as long = lbound(p_string)
    dim upper as long = ubound(p_string)
    dim index as long
    dim qb_string as string = ""
    for index = lower to upper
        if p_string(index) <> 0 then
            qb_string = qb_string + chr(p_string(index))
        else
            exit for
        end if
    next index
    return qb_string
end function

function get_data_size (value as double) as string
    if (value < 1000) then
        return str(value) + " Byte"
    end if
    if (value >= 1000000) then
        value = int(value / 100000 + 0.5) / 10
        return str(value) + " MB"
    end if
    value = int(value / 100 + 0.5) / 10
    return str(value) + " KB"    
end function

function get_date_string (time_stamp as double) as string
    return format(time_stamp, "yyyy-mm-dd hh:mm:ss") 
end function

function get_y_n () as ubyte
    dim answer as long = 0
    ' N, Y, n, y
    while answer <> 78 and answer <> 89 and answer <> 110 and answer <> 121
        answer = getkey
    wend
    ' Y, y
    if answer = 89 or answer = 121 then
        return 1
    else
        return 0
    end if
end function

'== Basic File Handling
'We have to mess around with that byref, because we cannot return an array...
'Loads an arbitrary file with the given name into the given ubyte array.
sub load_contents_from_file (file_name as string, file_contents() as ubyte)
    if fileexists(file_name) = 0 then
        handle_coding_error file_name + " was not found."
    end if
    dim file_size as long = FileLen(file_name)
    dim uboundary as long = file_size - 1
    'We use -1 as lower boundary as an indicator for a file being empty
    dim lboundary as long = -1
    if file_size > 0 then
        lboundary = 0
    end if
    redim file_contents(lboundary to uboundary)
    dim fh as long = freefile
    dim error_ocurred as integer = 0
    error_ocurred = open (file_name for random access as fh len = file_size)
    handle_open_error(error_ocurred, file_name, "reading")
    error_ocurred = get (# fh, 0, file_contents())
    handle_read_error(error_ocurred, fh, file_name)
    close (fh)
end sub

'This saves content to an arbitrary file.
'The contents are taken from the given ubyte array.
'Files already existing will be completely overwritten, with no tailing residual
'contents.
sub save_contents_to_file (file_name as string, file_contents() as ubyte)
    dim error_ocurred as integer = 0
    if fileexists(file_name) <> 0 then
        'Random will not overwrite tailing content, or remove it. So we have to
        'make sure, that the file does not contain anything, yet.
        error_ocurred = kill (file_name)
        handle_write_error(error_ocurred, file_name)
    end if
    dim file_size as long = ubound(file_contents) + 1
    dim fh as long = freefile
    'This already creates a file of size 0 bytes:
    error_ocurred = open (file_name for random access as fh len = file_size)
    handle_open_error(error_ocurred, file_name, "random")
    'The -1 case here only occurs, when the loaded file had a size of 0 bytes.
    'In such a case we don't need to write anything anyway.
    if lbound(file_contents) > -1 then
        error_ocurred = put (# fh, 1, file_contents())
        handle_write_error(error_ocurred, file_name)
    end if
    close(fh)
end sub

'Physically delets the file of the given name.
sub delete_file (file_name as string)
    dim error_code as long = kill(file_name)
    handle_deletion_error(error_code, file_name)
end sub

'Reduces the filexists debacle to a simple 1 or 0
function file_exists (file_name as string) as ubyte
    if fileexists(file_name) = -1 then
        return 1
    else
        return 0
    end if
end function

'Sets the file length of an existing file to the given value. Works in principle
'both ways, enlarging and shrinking a file. But here it is meant solely for
'shrinking an existing file, to free unused space occupied by the manager file.
sub truncate_file (file_name as string, file_size as ulong)
    if (file_exists(file_name) = 0) then
        handle_coding_error("Attempt of truncating not existing file " + _
                            file_name)
    end if
    dim error_code as long = 0
    dim file_handle as long = freefile
    error_code = open (file_name for binary access as #file_handle)
    handle_open_error(error_code, saves_file_name, "binary")
    ' + 1 because this is how it works. 128 bytes file length in the end needs
    ' 129 for the seek.
    seek #file_handle, file_size + 1
    ' This one *needs* FreeBasic 1.08 or newer.
    error_code = fileseteof(file_handle)
    handle_truncate_error(error_code, saves_file_name)
    close #file_handle
end sub

'Actually we do handle the concept of empty files (size = 0 bytes). But in the
'context of warlords saves 0 bytes files make no sense. They are either damaged,
'or someone tries to mess with us. In both cases, we don't want to work with
'those.
function get_file_size_from_content (file_contents() as ubyte) as uinteger
    if lbound(file_contents) = -1 then
        return 0
    else
        return ubound(file_contents) + 1
    end if
end function

'This calculates a simple (literal) check sum from file contents.
function get_checksum_from_content (file_contents() as ubyte) as ulong
    if lbound(file_contents) = -1 then return 0
    dim sum as ulong = 0
    dim index as uinteger
    dim start as uinteger = lbound(file_contents)
    dim end_ as uinteger = ubound(file_contents)
    'This loop my overflow, but that's OK. Assuming that a check happened,
    'whether the compared files are of same size, this is OK. The probability,
    'that the two collide may not be as nice as with modern hash sums. But it's
    'fairly fast and OK for our kind of job.
    for index = start to end_
        sum = sum + file_contents(index)
    next index
    return sum
end function

'==== Actual Application Functions ====
'== References Stuff ==
'These guys here manage the reference area of the file, where all the pointers
'to the actual file contents in the data area are stored.
function open_references () as long
    dim error_code as long = 0
    dim file_handle as long = freefile
    error_code = open (saves_file_name _
                       for random _
                       as #file_handle len = ref_block_size)
    handle_open_error(error_code, saves_file_name, "random")
    return file_handle
end function

'Reads the meta data part of our saves file
sub load_references ()
    redim references(1 to max_ref_records)
    dim file_handle as long = open_references()
    dim error_code as long = 0
    dim index as ubyte
    'This part might be re-written with all elements en bloc read
    for index = 1 to max_ref_records
        error_code = get (#file_handle, index, references(index))
        handle_read_error(error_code, file_handle, saves_file_name)
    next index
    close file_handle
end sub

'Writes the meta data part of our saves file
sub save_references ()
    dim file_handle as long = open_references()
    dim error_code as long = 0
    dim index as ubyte
    'This part might be re-written with all elements en bloc written
    for index = 1 to max_ref_records
        error_code = put (#file_handle, index, references(index))
        handle_write_error(error_code, saves_file_name)
    next index
    close file_handle
end sub

'How much space is our saves blob taking up on the disk?
function get_manager_size () as ulong
    return FileLen(saves_file_name)
end function

'This checks whether two references are technically the same, as in, they
'reference the same section of the saves file.
function references_equal (a as reference_record, _
                           b as reference_record) as ubyte
    if a.start = b.start and a.end_ = b.end_ and a.deleted = b.deleted then
        return 1
    else
        return 0
    end if
end function

'References are to be sorted by their deletion state and their starting offset.
'Technically speaking, the end might also be of some relevance. But in practice
'it should never make an observable difference.
function reference_greater_then (a as reference_record, _
                                 b as reference_record) as ubyte
    'We *must* assume, that there is no overlap.
    '1 > 0, deleted are supposed to be at the end
    if a.deleted > b.deleted then
        return 1
    else
        'The later they start, the further down.
        if a.deleted = b.deleted then
            if a.start > b.start then
                return 1
            else
                if a.start = b.start then
                    'Every thing is the same, so the later the end, the further
                    'down.
                    if a.end_ > b.end_ then
                        return 1
                    else
                        'a.end_ < b.end_ OR a = b case
                        return 0
                    end if
                else
                    'a.start < b.start case
                    return 0
                end if
            end if
        else
            'a.deleted < b.deleted case
            return 0
        end if
    end if
end function

'Note: This does not really sort a whole lot of stuff. It only walks over the
'references once, no more. It is meant to be used every time after someone
'deletes or adds a record. When adding a file, the new reference will be at the
'last position. Going through the elements from last to first will work similar
'to an insert sort. As only one file can be missaligned, only one pass is
'required. Same for the deletion. But here we have to go from start to end, as
'it will always be before all the previously deleted records. Going from 1st to
'last makes them go to their proper place automatically.
sub sort_references (after_deletion as ubyte)
    dim start as ubyte = 1
    dim end_ as ubyte = max_ref_records - 1
    dim step_size as integer = 1
    if after_deletion = 0 then
        swap start, end_
        step_size = -1
    end if
    for index as uinteger = start to end_ step step_size
        if reference_greater_then(references(index), references(index + 1)) then
            swap references(index), references(index + 1)
        end if
    next index
end sub

'This basically collects all the empty parts between saves in the manager and
'adds their size. Note: If the manager is somehow faulty, this might give bogus
'results. In such a case there is basically only one thing you can do: Delete
'the saves that the check_manager_integrity identifies as faulty. If the meta
'data range is affected, then you can basically forget it and have to start with
'a new empty manager save. (Delete the faulty one, the rest is done by the
'manager.)
function get_unused_manager_space () as long
    load_references()
    dim unoccupied as long = 0
    dim manager_size as ulong = get_manager_size()
    dim last_index as ubyte = 1
    dim index as ubyte
    if references(1).deleted = 0 then
        'Even before the very first file there might be unused disk space.
        unoccupied = references(1).start - data_start_offset
    else
        'Not one single slot in use? Then everything except the meta data is
        'unused disk space!
        return manager_size - data_start_offset + 1
    end if
    for index = 1 to max_ref_records - 1
        'When the next guy is unused, it means we reached the end. No more gaps.
        if references(index + 1).deleted = 1 then exit for
        last_index = index + 1
        unoccupied += (references(index + 1).start - references(index).end_ - 1)
    next index
    'Even after the very last file in the manager there might be unused space.
    unoccupied += (manager_size - references(last_index).end_)
    return unoccupied
end function

'For debugging purposes
sub print_dump_line (index as ubyte)
    print " " + str(index) + "|" + _
          str(references(index).deleted) + "|" + _
          str(references(index).start) + "|" + _
          str(references(index).end_) + "|" + _
          references(index).description + "|" + _
          get_date_string(references(index).time_stamp) + "|" + _
          str(references(index).check_sum)
end sub

'More debugging means
sub dump_references (with_deleted as ubyte)
    print "dump_references " + str(with_deleted)
    print "Data starts at: " + str(data_start_offset)
    dim index as ubyte
    for index = 1 to max_ref_records
        if (references(index).deleted = 1 and index > with_deleted) then
            exit for
        end if
        print_dump_line(index)
    next index
    dim wasted as ulong = get_unused_manager_space()
    wait_for_enter("Wasted space: " + str(wasted))
    print
end sub

'Does what is advertised. This gives the index in the references, that is the
'first one after the occupied ones. If not one single slot is free, returns
'references_depleted.
function get_first_empty_reference_slot () as ubyte
    for index as ubyte = 1 to max_ref_records
        if references(index).deleted = 1 then
            return index
        end if
    next index
    
    'OK, all of them are occupied.
    return references_depleted
end function

'Checks whether the reference area has still at least one slot free.
function got_empty_reference_slot () as ubyte
    'if the last one is empty, then yes, we got (at least) one.
    return references(max_ref_records).deleted
end function

'Scans the indizes of all occupied slots for enough space in-between the
'referenced files to squeeze in a new file of the given size.
'If the references indicate, that all slots are in use, the function returns
'references_full_offset.
'If there is at least one slot free, it returns the starting offset a new file
'can begin occupying. This can of course be the room just after the last file.
'This implicitly will cause the problem, that deleting files may leave gaps for
'a while or indefinitely, if every newly added file is just too big to use the
'freed up space. This can be freed up with deflate().
function get_first_fitting_data_offset (file_size as uinteger) as uinteger
    dim last_element_index as ubyte
    dim first_empty_index as ubyte = get_first_empty_reference_slot()
    if first_empty_index = 1 then
        'This is the first index, so no files yet. So starts directly after the
        'references
        return data_start_offset
    end if
    if first_empty_index = references_depleted then
        'All slots are in use, so the last one's boundary + 1 would be OK.
        'Although that's actually academic, because if all slots are in use, no
        'File can be added anyway... This case must be catched by the caller.
        return references_full_offset
    end if
    last_element_index = first_empty_index - 1
    if last_element_index = 1 then
        'There is exactly one file in there, yet. So the new one has to either
        'start directly after the first file (not enough space before it), or is
        'placed right at the beginning.
        if (references(1).start >= (file_size + data_start_offset)) then
            'Enough space before the element
            return data_start_offset
        else
            'OK, can only fit after the first one.
            return references(1).end_ + 1
        end if
    end if
    for index as ubyte = 1 to last_element_index - 1
        dim start_gap as uinteger = references(index).end_ + 1
        dim end_gap as uinteger = references(index + 1).start - 1
        'Special case: The first element might be preceeded by a gap!
        if index = 1 then
            if (references(index).start - data_start_offset) >= file_size then
                return data_start_offset
            end if
        end if
        if (    (start_gap < end_gap) _
            and ((end_gap - start_gap + 1) >= file_size)) then return start_gap
    next index
    'We did not find any gaps with enough space, so we append it at the end.
    return references(last_element_index).end_ + 1
end function

'This creates a new reference from a file blob, including check sum and
'boundaries. It misses the description, which needs to be added manually. Once
'this is done, the contents are ready to save, along with the reference.
function get_new_reference_for_file (file_contents() as ubyte) as reference_record
    dim file_size as uinteger = get_file_size_from_content(file_contents())
    dim new_reference as reference_record
    new_reference.deleted = 0
    new_reference.start = get_first_fitting_data_offset(file_size)
    new_reference.end_  = new_reference.start - 1 + file_size
    new_reference.check_sum = get_checksum_from_content(file_contents())
    'This implies we oughta use that immediately:
    new_reference.time_stamp = now()
    return new_reference
end function

'This looks up the reference quealling the handed on and returns its index in
'the reference list. Note: this does not necessarily mean, physically the same
'reference (aka address in memory).
function get_reference_index (reference as reference_record) as ubyte
    'This could probably be written a bit more efficient, considering, that the
    'list is supposed to be sorted by deleted, start and end_
    dim index as ubyte
    for index = 1 to max_ref_records
        if references_equal(reference, references(index)) then return index
    next index
    return reference_missing
end function

'Checks whether a reference with the same properties (location and deletion
'state) already exists.
function reference_exists (reference as reference_record) as ubyte
    dim index as ubyte = get_reference_index(reference)
    if index = reference_missing then
        return 0
    else
        return 1
    end if
end function

'Takes a given reference element and adds it to the reference list. Note that
'this should essentially happen fairly soon after creating a new reference.
function add_reference (reference as reference_record) as ubyte
    if reference_exists (reference) then
        handle_coding_error("This reference already exists. Cannot add it " + _
                            "to table.")
    end if
    if reference.deleted = 1 then
        handle_coding_error("This reference was deleted. Cannot add it to " + _
                            "table.")
    end if
    dim index as ubyte = get_first_empty_reference_slot()
    if index = references_depleted then
        return references_table_full
    end if
    references(index) = reference
    sort_references(0)
    save_references()
    return index
end function

'Flags an existing reference of the list as deleted and sorts it into the
'deleted section of the list, at the end.
function delete_reference (byref reference as reference_record) as ubyte
    if reference.deleted = 1 then
        handle_coding_error "Attempt to delete an already deleted record: " + _
                            str(reference.start) + "/" + str(reference.end_)
    end if
    'This will not find already deleted references due to reference.deleted = 0!
    dim index as ubyte = get_reference_index(reference)
    if index = reference_missing then
        return reference_missing
    end if
    reference.deleted = 1 'This should make the record end up at the end
    sort_references(1)
    save_references()
    return reference_deleted
end function

'Basically the number of occupied slots.
function get_reference_max_index () as ubyte
    dim max_references as ubyte = get_first_empty_reference_slot() - 1
    if max_references + 1 = references_depleted then
        max_references = max_ref_records
    end if
    return max_references
end function

'Should actually not be necessary. But we have it available.
sub check_index_validity (index as ubyte)
    if index > max_ref_records then
        handle_coding_error("Ref index my be " + str(max_ref_records) + "tops.")
    end if
end sub

'Pagination depends on the maximum number of elements per page and the maximum
'number of references actually being occupied. The index here is the element in
'question. For knowing the number of pages total, it'd require the number of
'occupied slots.
function get_page_from_index (index as ubyte) as ubyte
    check_index_validity(index)
    dim rest as ubyte = 0
    dim page as ubyte
    rest = index mod records_per_page
    page = index \ records_per_page
    if rest > 0 then
        page = page + 1
    end if
    return page
end function

'This calculates the maximum page that could ever happen, if all references were
'used at once.
function get_max_page () as ubyte static
    dim max_page as ubyte
    'Poor man's caching...
    if max_page = 0 then max_page = get_page_from_index(max_ref_records)
    return max_page
end function

'Checks out whether the page is exceeding the current maximum number of pages.
'If so, it stops the application.
sub check_page_validity (page as ubyte)
    if (page = 0) then handle_coding_error("Pages must be > 0!")
    dim max_pages as ubyte = get_max_page()
    if page > max_pages then
        handle_coding_error("Pages must be < " + str(max_pages) + "!")
    end if
end sub

'Once a page has been selected, the list of elements consists basically of
'the starting element for that page up to the last element being displayed. This
'here gets the index of the first element.
function get_start_index_for_page (page as ubyte) as ubyte
    check_page_validity(page)
    return (page - 1) * records_per_page + 1
end function

'And this here gives the index for the last element of that list. Note, tat this
'ignores the info, whether the element is currently deleted or the index is
'greater than the maximum number of available slots.
function get_end_index_for_page (page as ubyte) as ubyte
    check_page_validity(page)
    return page * records_per_page
end function

'Prints the meta data of a save slot given by the index.
sub print_reference_line(index as ubyte)
    check_index_validity(index)
    dim reference as reference_record = references(index)
    dim size as uinteger = reference.end_ - reference.start + 1
    dim kb as uinteger = int(size / 1000 + 0.5)
    dim time_stamp as string = get_date_string(reference.time_stamp)
    'This little maneuver here removes the zero bytes, which allows for a proper
    'length assessment in the next step.
    dim description as string = reference.description
    if len(description) < description_max_size then
        print using "###  ####, kB & &"; index; kb; time_stamp; reference.description
    else
        'Let's use all the space we have available.
        print using "###  ####, kB & &"; index; kb; time_stamp; reference.description;
    end if
end sub

'Prints exactly one page of references, the given one.
sub print_references_page (page as ubyte)
    dim max_references as ubyte = get_reference_max_index()
    if max_references = references_empty then
        print "There are no saved games stored in the manager right now."
    else
        dim max_page as ubyte = get_page_from_index(max_references)
        dim start_index as ubyte = get_start_index_for_page(page)
        dim end_index as ubyte = get_end_index_for_page(page)
        if end_index > max_references then end_index = max_references
        dim index as ubyte
        print "Page " + str(page) + " of " + str(max_page)
        print "No. File Size Added at            Description"
        for index = start_index to end_index
            print_reference_line(index)
        next index
    end if
end sub

'This allows the user to select a save from the manager by entering its slot
'number. It displays the saves paginated.
function pick_manager_save (heading as string, prompt as string) as ubyte
    load_references()
    dim last_page as uinteger = 0
    dim max_index as ubyte = get_reference_max_index()
    dim max_page as ubyte = int(max_index / records_per_page)
    if (max_index mod records_per_page) > 0 then max_page += 1
    dim min_page as ubyte = 1
    if (max_page < min_page) then max_page = min_page
    dim current_page as ubyte = min_page
    dim last_key as long = 0
    dim current_row as integer
    dim current_number as string = ""
    dim error_message as string = ""
    if max_index = references_empty then 
        wait_for_enter("Currently no games available in manager. " _
                       + "Press Enter to return to main menu.")
        return 0
    end if
    while last_key <> 27 and last_key <> 13
        select case last_key
            case 8 ' Backspace
                if len(current_number) > 0 then
                    current_number = left(current_number, _
                                          len(current_number) - 1)
                end if
            case 20991 'Down
                if current_page < max_page then current_page += 1
            case 18943 'Up
                if current_page > min_page then current_page -= 1
            case 48 '0
                if len(current_number) > 0 and len(current_number) < 3 then
                    dim new_number as string = current_number
                    new_number = new_number + chr(last_key)
                    if (val(new_number) <= max_index) then
                        current_number = new_number
                    end if
                end if
            case 49 to 57 '1 - 9 
                if len(current_number) < 3 then
                    dim new_number as string = current_number
                    new_number = new_number + chr(last_key)
                    if (val(new_number) <= max_index) then
                        current_number = new_number
                    end if
                end if
        end select

        if last_page <> current_page then
            cls
            print heading
            print_references_page(current_page)
            last_page = current_page
            current_row = csrlin
        end if
        locate current_row, 0
        'Don't make this a " "; at the end. It will break the locate above...
        print prompt + current_number + " "
        last_key = GetKey
    wend
    'When the user aborts this, 0 is the marker to indicate this.
    if last_key = 27 then current_number = "0"
    return val(current_number)
end function

'== Saves Functions ==
'These functions manage mostly loading and saving of saved game files, like in
'actual Warlords save files.
'The game saves are all stored as files War1.sav to War8.sav. If a sav file does
'not exist, there simply has not yet been saved a game in that slot.
'The first 15 bytes + 1 null byte may make up the save game name. The null byte
'terminates the string. (Thanks, C, I suppose...)
'As the map is basically static, only added towers, city defense level
'information and cities being razed and their ownership status may varry.
'The state of ruins saved is probably only if they have been explored and what
'is hidden in them. But when evaluating the contents, essentially the whole map
'is also part of the save.
'Save games can probably get as big as they want, just as long as the RAM is
'enough to handle the existing units and towers added. The rest seems mostly
'static/always existing.

'I refuse to mess around with 0-based indizes, when the reality is, that the
'file names work with natural numbers.
dim shared wl_saves(1 to 8) as wl_save_file
dim shared saves_initialized as byte = 0

'This one creates the saves stache anew, no payload in form of actual files,
'only empty references (deleted).
sub initialize_saves_file ()
    if file_exists(saves_file_name) = 1 and force_init = 0 then return
    dim problem_occurred as ubyte = 0
    if file_exists(saves_file_name) = 1 then
        problem_occurred = kill (saves_file_name)
        handle_write_error(problem_occurred, saves_file_name)
    end if
    dim file_handle as long = freefile
    dim dummy_record as reference_record
    dummy_record.start = 0
    dummy_record.end_ = 0
    dummy_record.deleted = 1
    dummy_record.description = ""
    dummy_record.time_stamp = 0
    problem_occurred = open (saves_file_name _
                             for random _
                             as #file_handle len = ref_block_size)
    handle_open_error (problem_occurred, saves_file_name, "random")
    dim index as ubyte
    for index = 1 to max_ref_records
        problem_occurred = put (#file_handle, index, dummy_record)
        handle_write_error(problem_occurred, saves_file_name)
    next index
    close (file_handle)
end sub

'This one only checks, if there is a warlords.exe. Could technically be any file
'as we never check its contents. But then again, I'm not responsible for someone
'who places this program here in a folder with a bogus warlords.exe file. And
'even if: If it does not magically also use war1.sav to war8.sav, there's no
'actual harm done, when not checking the file contents.
sub ensure_warlords_folder ()
    dim wlexe as string = "warlords.exe"
    if fileexists(wlexe) = 0 then
        wait_for_enter(wlexe + " was not found. Start this from within " + _
                       "your Warlords folder.")
        system not_warlords_folder
    end if
end sub

'Saves are between 1 and 8, nothing else.
sub ensure_valid_save_number (number as ubyte)
    if number < 1 or number > 8 then
        handle_coding_error "Save file number out of boundary: " + str(number)
    end if
end sub

'Warlords' saved game files are named war1.sav to war8.sav. So giving the index
'from 1 to 8 gives you the file name of the actual file.
function get_save_file_name (number as ubyte) as string
    ensure_valid_save_number(number)
    return "war" + str(number) + ".sav"
end function

'This marks the save file at the index to be existing in our meta data.
sub set_save_exists(index as ubyte, new_value as ubyte)
    ensure_valid_save_number(index)
    if not new_value = 1 and not new_value = 0 then
        handle_coding_error("Save existence value must be 0 or 1!")
    end if
    wl_saves(index).exists = new_value
end sub

'This stores the saved game file size in our meta data.
sub set_save_size(index as ubyte, new_value as uinteger)
    ensure_valid_save_number(index)
    wl_saves(index).size = new_value
end sub

'This stores the actual in-game saved game file description in our meta data.
sub set_save_name (index as ubyte, new_name as string)
    ensure_valid_save_number(index)
    wl_saves(index).name = new_name
end sub

'Before working with Warlord's saved game files, we should get an idea of which
'files actually exist, and what properties they have. This function collects
'exactly this kind of meta data.
sub initialize_wl_saves ()
    dim file_name_index as ushort
    dim file_name as string
    for file_name_index = 1 to 8
        file_name = get_save_file_name(file_name_index)
        if fileexists(file_name) = 0 then
            set_save_exists(file_name_index, 0)
            set_save_size(file_name_index, 0)
        else
            set_save_exists(file_name_index, 1)
            set_save_size(file_name_index, FileLen(file_name))
            dim fh as long = freefile
            dim error_ocurred as integer = 0
            error_ocurred = open (file_name for random access as fh len = 16)
            handle_open_error(error_ocurred, file_name, "random")
            dim buffer(0 to 15) as ubyte
            get # fh, 0, buffer()
            close(fh)
            set_save_name(file_name_index, _
                          get_qb_string_from_pascal_string(buffer()))
        end if
    next file_name_index
    saves_initialized = 1
end sub

'The names of the 8 saved games or Warlords are shown, including their numbers
'and file sizes.
sub print_warlords_file_list (with_missing as ubyte)
    dim save_index as ubyte
    dim save_file_name as string
    initialize_wl_saves()
    for save_index = 1 to 8
        save_file_name = get_save_file_name(save_index)
        if wl_saves(save_index).exists then
            dim kb as uinteger = int(wl_saves(save_index).size / 1000 + 0.5)
            print using "# (#, kB) &"; save_index; kb; wl_saves(save_index).name
        else
            if (with_missing = 1) then 
                'Except for the brackets, the term is literally taken from WL.
                print str(save_index) + " <not used>"
            end if
        end if
    next save_index
    print
end sub

'Checks if the file with saved game of the given number actually exists.
function save_no_exists (number as ubyte) as ubyte
    return file_exists(get_save_file_name(number))
end function

'This saves the given contents of the ubyte array to the saved game with the
'given number. Existing saves will be overwritten, containing only the given
'contents afterwards.
sub save_contents_to_save (save_number as ubyte, file_contents() as ubyte)
    save_contents_to_file(get_save_file_name(save_number), file_contents())
end sub

'This loads all the contents from the saved game with the given number into the
'given ubyte array.
'The resulting array has the exact same size as the file.
sub load_save_contents (save_number as ubyte, file_contents() as ubyte)
    load_contents_from_file(get_save_file_name(save_number), file_contents())
end sub

'Deletes the physical Warlords saved game file matching the given number.
sub delete_save_file (number as ubyte)
    dim file_name as string = get_save_file_name(number)
    delete_file(file_name)
end sub

'Essentially asks for a number between 1 and 8. If the user enteres a different
'digit, or uses one of a saved game, that does no exist, the input is ignored.
'If the allow_empty value is set, then even those can be selected by the user.
'If he presses ESC, then zero is returned, indicating this aborting to the
'caller. The prompt is displayed only once.
function get_warlords_save_no_from_user (prompt as string, _
                                         allow_empty as ubyte) as ubyte
    dim answer as long = 0
    dim save_file_number as ubyte = 0
    print prompt;
    do
        ' 1-8, ESC
        while (answer < 49 or answer > 56) and answer <> 27
            answer = GetKey
        wend
        if answer = 27 then return 0
        save_file_number = answer - 48
        if allow_empty = 0 and wl_saves(save_file_number).exists = 0 then
            save_file_number = 0
            answer = 0
        end if
    loop while save_file_number = 0
    print save_file_number
    return save_file_number
end function

'Prints the list of available physical Warlords saved games files and asks the
'user to select one of them by number. Only existing files can be selected. Note
'that zero value indicates the user aborted the selection of the file.
'The context is basically the heading, while the prompt is displayed to the
'instructing him to do something. (Can be deletion or loading the file into the
'manager.)
function pick_warlords_save (context as string, prompt as string) as uinteger
    cls
    print context
    print "Available saves:"
    print_warlords_file_list(0)
    dim save_file_number as ubyte = get_warlords_save_no_from_user(prompt, 0)
    return save_file_number
end function

'==== Data-Area Functions ====
'These guys here manage the data area of the saves blob.
'The file consists of two areas, the meta data of used save slots, and the
'actual saved game data, coming right after the slot information.
'Each slot "record" consists of a description text and the location of the
'actual file contents referenced by it. The file contents may varry in size.
'This is why it is necessary to keep track of those records in the reference
'area.

'Opens the save stache for later operations reading or writing actual saved game
'data records.
function open_contents_location () as long
    dim error_code as long = 0
    dim file_handle as long = freefile
    error_code = open (saves_file_name for binary access as #file_handle)
    handle_open_error(error_code, saves_file_name, "binary")
    return file_handle
end function

'This stores bytes from a saved game file into the data-area of the stache.
'It needs an offset to be used inside the data-area.
'Important: The offset must also include the header size occupied by the
'references area. So it is an actual physical offset.
sub save_contents_to_location (file_contents() as ubyte, offset as uinteger)
    if (offset = references_full_offset) then
        handle_coding_error("Attempting to save content to data area when " + _
                            "references indicated no slots free.")
    end if
    if (offset < data_start_offset) then
        handle_coding_error("Attempting to save content to reference area.")
    end if
    dim error_code as long = 0
    dim file_handle as long = open_contents_location ()
    dim start as uinteger = offset
    error_code = put (#file_handle, start, file_contents())
    handle_write_error(error_code, saves_file_name)
    close (file_handle)
end sub

'Loads the contents from the saved game data area. It needs the target array, to
'which the contents are to be loaded, and the start and end offset where to look
'for the actual data.
sub load_contents_from_location (file_contents() as ubyte, _
                                 start_offset as uinteger, _
                                 end_offset as uinteger)
    'Basic can be so fucking weird. This ensures that we read exactly the right
    'amount of bytes from the stache. Using the data amount explicitly won't
    'work.
    if (start_offset < data_start_offset) then
        handle_coding_error("Attempting to read content from reference area.")
    end if
    dim file_length as uinteger = end_offset - start_offset + 1
    redim file_contents(file_length - 1)
    dim error_code as long = 0
    dim file_handle as long = open_contents_location ()
    error_code = get(#file_handle, start_offset, file_contents())
    handle_read_error(error_code, file_handle, saves_file_name)
    close (file_handle)
end sub

'This loads the saved game data saved in the data area of the manager,
'referenced by the given reference element. The destination array must also be
'given. The loaded conents end up in there.
sub load_contents_referenced (file_contents() as ubyte, _
                              reference as reference_record)
    load_contents_from_location(file_contents(), _
                                reference.start, _
                                reference.end_)
end sub

'This is meant more like re-place (place again), not replace!
'It takes the contents of the file referenced by the reference with the given
'index, reads them, and saves them a little bit closer to the beginning/meta
'data area, so that any unused gaps are moved to the end of the files. When done
'in sequence, all unused space will condense at the end eventually.
function re_place_save (index as ubyte) as uinteger
    'Getting existing slot data
    dim file_contents() as ubyte
    dim description as string = references(index).description
    dim time_stamp as double = references(index).time_stamp
    load_contents_referenced(file_contents(), references(index))
    'Removing old slot
    delete_reference(references(index))
    'Re-Adding contents, this should end up at the earliest place available.
    'Worst case: This is the exact same place we just removed content from.
    dim new_reference as reference_record
    new_reference = get_new_reference_for_file(file_contents())
    new_reference.description = description
    new_reference.time_stamp = time_stamp

    save_contents_to_location(file_contents(), new_reference.start)
    add_reference(new_reference)
    return new_reference.end_
end function

'This function takes the information of the meta data slot given by the index
'provided and checks out, whether it is intact. The result is a ubyte value,
'that contains all possibly found errors in form of flags.
'No checks on the sort order of the meta data are done! Those must be done
'separately.
function check_slot_integrity (slot as ubyte) as ubyte
    dim lower_offset_boundary as uinteger = data_start_offset
    dim upper_offset_boundary as uinteger = get_manager_size()
    if (references(slot).deleted = 1) then return 0
    dim flags as ubyte = 0
    if     references(slot).start > references(slot).end_ _
        or references(slot).start < lower_offset_boundary _
        or references(slot).end_  < lower_offset_boundary _
        or references(slot).start > upper_offset_boundary _
        or references(slot).end_  > upper_offset_boundary _
    then
        'Boundary faulty flag
        flags += boundary_error_flag
    end if
    dim file_contents() as ubyte
    load_contents_referenced(file_contents(), references(slot))
    dim checksum_from_file as ulong = get_checksum_from_content(file_contents())
    if checksum_from_file <> references(slot).check_sum then
        'Checksum faulty flag
        flags += check_sum_error_flag
    end if
    return flags
end function

'This function goes over the list of slots and checks each one of them for
'problems. If a slot is found to be faulty, it will be listed, along with some
'information of the kind of flaws this slot has.
sub show_faulty_slots ()
    cls
    print "Checking manager saves for problems:"
    dim flags as ubyte = 0
    dim got_b_or_c as ubyte = 0
    dim got_s as ubyte = 0
    for index as ubyte = 1 to max_ref_records
        print str(index) + " ";
        flags = check_slot_integrity(index)
        if flags and boundary_error_flag then
            print "b";
            got_b_or_c = 1
        end if
        if flags and check_sum_error_flag then
            print "c";
            got_b_or_c = 1
        end if
        if index > 1 and index < max_ref_records then
            if     references(index - 1).deleted <> references(index).deleted _
                or references(index).deleted <> references(index + 1).deleted _
            then
                print "s";
                got_s = 1
            end if
            flags = flags or sort_error_flag
        end if
        if flags = 0 then
            print "OK";
        end if
        print "   ";
    next
    print
    if got_b_or_c = 1 then
        print "Saves with b or c cannot be helped. They have to be deleted."
    end if
    if got_s = 1 then
        print "Saves with s may be helped, use maintenances tools."
    end if
    if got_b_or_c = 0 and got_s = 0 then
        print "All OK."
    end if
    wait_for_esc("Press ESC to retorn to maintenance menu.")
end sub

'Checks out all slots as well as all file contents.
'We expect errors() to have indices 0 to 2
sub check_manager_integrity (errors() as ubyte)
    load_references()
    dim integrity as ubyte = 0
    dim boundary_errors as ubyte = 0
    dim check_sum_errors as ubyte = 0
    dim sort_errors as ubyte = 0
    dim crossed_into_deleted as ubyte = 0
    dim last_end as uinteger = data_start_offset - 1
    for index as ubyte = 1 to max_ref_records
        if references(index).deleted = 1 then crossed_into_deleted = 1
        if crossed_into_deleted = 1 and references(index).deleted = 0 then
            sort_errors += 1
            crossed_into_deleted = 0
        end if
        if references(index).deleted = 0 then
            integrity = check_slot_integrity(index)
            if integrity and boundary_error_flag then
                boundary_errors += 1
            end if
            if references(index).start < last_end then
                boundary_errors += 1
            end if
            if integrity and check_sum_error_flag then
                check_sum_errors += 1
            end if
            last_end = references(index).end_
        end if
    next 
    errors(0) = boundary_errors
    errors(1) = check_sum_errors
    errors(2) = sort_errors
end sub

'This assumes, that the manager has no faulty records. Make sure it is so!
'Otherwise you might fuck up all the remaining working data in there.
'It basically moves all the saved data closer together, so that there are no
'gaps between the saves. This way all the empty space will end up at the end of
'the stache file. It will then be shrunk to the offset where the last actual
'payload is loacted, leaving 0 bytes wasted, eventually.
sub deflate ()
    load_references()
    cls
    print "Deflating manager save. Depending on the disk type and amount " + _
          "of data, this can take quite some time... ";
    dim last_end as ulong = 0
    for index as ubyte = 1 to max_ref_records
        if references(index).deleted = 1 then exit for
        print str(index) + " ";
        last_end = re_place_save(index)
    next
    print "shrinking file..."
    'Now that we have potentially freed up space, we have to shrink the actual
    'manager saves file to the size of its contents:
    truncate_file(saves_file_name, last_end)
    print "Deflating finished."
end sub

'Displays the current status of the warlords manager file. This includes faulty
'data and potential disk space that can be reclaimed.
function show_status () as long
    dim file_size_value as ulong = get_manager_size()
    dim file_size as string = get_data_size(file_size_value)
    dim errors(2) as ubyte
    cls
    print "Checking manager integrity, please wait..."
    check_manager_integrity(errors())
    dim wasted_value as long = -1
    dim wasted as string
    if errors(0) = 0 and errors(1) = 0 and errors(2) = 0 then
        wasted_value = get_unused_manager_space()
        wasted = get_data_size(wasted_value)
    end if
    cls
    print "Manager Status"
    print "Manager file size:           " + file_size
    print "Saves stored in manager:     " + str(get_reference_max_index())
    if wasted_value = -1 then
        print "Wasted space was not calculated due to data integrity problems:"
    else
        print "Currently wasted space:      " + wasted
    end if
    if errors(0) > 0 then
        print "Boundary errors in manager:  " + str(errors(0))
    end if
    if errors(1) > 0 then
        print "Check sum errors in manager: " + str(errors(1))
    end if
    if errors(2) > 0 then
        print "Sort errors in manager:      " + str(errors(2))
    end if
    dim fraction_unused as double = wasted_value / file_size_value
    if wasted_value > 0 and fraction_unused > 0.25 then
        print str(int(fraction_unused * 100 + 0.5)) + _
              " % wasted manager space (" + wasted + _
              ") indicate a certain benefit of deflating the file."
    end if
    return wasted_value
end function

'==== Main Functions ====
'These are the actual user functionality functions
'Takes data from the manager and saves it to an actual Warlords save file.
sub transfer_to_file ()
    dim manager_index as ubyte = _
        pick_manager_save("Transfer manager save to Warlords", _
            "Pick game number to be transferred to Warlords (press ESC to " + _
            "abort): ")
    if manager_index = 0 then exit sub
    dim manager_reference as reference_record = references(manager_index)
    dim warlords_index as ubyte = 0
    while warlords_index = 0
        cls
        print_warlords_file_list(1)
        warlords_index = get_warlords_save_no_from_user( _
            "Pick the save slot where the data of save '" + _
            manager_reference.description + "' should be transferred " + _
            "to: ", 1)
        if warlords_index = 0 then exit sub
        if (wl_saves(warlords_index).exists = 1) then
            print "Slot " + str(warlords_index) + " is currently occupied " + _
                "by " + wl_saves(warlords_index).name + "."
            print "Do you want to overwrite this file? (y/n)"
            dim answer as ubyte = get_y_n()
            if answer = 0 then warlords_index = 0
        end if
    wend
    dim file_contents() as ubyte
    load_contents_referenced(file_contents(), manager_reference)
    dim checksum as ulong = get_checksum_from_content(file_contents())
    if checksum = manager_reference.check_sum then
        if (wl_saves(warlords_index).exists = 1) then
            print "Overwriting Warlords save " + str(warlords_index) + " (" + _
                  wl_saves(warlords_index).name + ") with manager save " + _
                  str(manager_index) + " (" + manager_reference.description + _
                  ")..."
        else
            print "Saving manager save " + str(manager_index) + " (" + _
                  manager_reference.description + ") as Warlords save " + _
                  str(warlords_index) + "..."
        end if
        save_contents_to_save(warlords_index, file_contents())
        print "Successfully saved file."
    else
        print "Checksum error: Manager index says " + _
              str(manager_reference.check_sum) + " while file contents " + _
              "from manager calculate to " + str(checksum) + _
              ". Manager store is corrupt. Cannot proceed savely."
    end if
    wait_for_enter("Press Enter to return to main menu.")
end sub

'Loads an actual Warlords saved game file and stores it in the manager.
sub transfer_to_manager()
    load_references()
    if got_empty_reference_slot() = 0 then
        wait_for_enter("There are currently no save slots available in the " + _
                       "manager. Please free up slots, before adding new " + _
                       "saves.")
        exit sub
    end if
    dim save_file_number as ubyte = _
        pick_warlords_save( _
            "Transfer Warlords save to manager", _
            "Select the save file to be transferred to the manager or " + _
            "press ESC to return to main menu: ")
    if save_file_number = 0 then exit sub
    dim error_message as string = ""
    print "Selected save " + str(save_file_number) + " (" + _
          wl_saves(save_file_number).name + ")."
    print "Please enter a description for the file manager to use"
    print "(max. " + str(description_max_size) + " characters, press ESC " + _
          "to abort):"
    dim enter_line as integer = CsrLin
    dim new_description as string = ""
    dim new_character as long = 0
    while new_character <> 27 and new_character <> 13
        locate enter_line, 0
        'Magic space makes the last character vanish when backspacing
        print new_description + " "
        new_character = getkey
        if new_character = 27 then
            print
            wait_for_enter("Aborting. Press Enter to return to main menu.")
            exit sub
        end if
        'We only want real ASCII here, not some control characters like PG UP
        if new_character > 31 and new_character < 256 then
            if len(new_description) < description_max_size then
                new_description += chr(new_character)
            end if
        end if
        if new_character = 8 then
            if len(new_description) > 0 then
                new_description = left(new_description, _
                                       len(new_description) - 1)
            end if
        end if
    wend
    dim save_file_contents() as ubyte
    print "Loading save " + str(save_file_number) + "..."
    load_save_contents(save_file_number, save_file_contents())
    dim new_reference as reference_record
    new_reference = get_new_reference_for_file(save_file_contents())
    new_reference.description = new_description
    print "Saving as " + new_description + "..."
    save_contents_to_location(save_file_contents(), new_reference.start)
    add_reference(new_reference)
    wait_for_enter("Finished. Press Enter to get back to the main menu.")
end sub

'Removes a save from the manager. Note: Does not free up disk space occupied by
'it. This is done by deflate().
sub delete_from_manager ()
    dim deletion_index as ubyte = _
        pick_manager_save("Delete Warlords save from manager", _
            "Pick game number to be deleted (press ESC to abort): ")
    if deletion_index = 0 then exit sub
    print "Are you sure you want to delete save " + str(deletion_index) + _
          " (" + references(deletion_index).description + ") from the " + _
          "manager? (y/n)"
    dim answer as ubyte = get_y_n()
    if answer = 1 then
        print "Removing save " + str(deletion_index) + " from manager..."
        delete_reference(references(deletion_index))
    else
        print "Skipping deletion."
    end if
    wait_for_enter("Press Enter to return to main menu.")
end sub

'Removes a physical Warlords save from the harddrive.
sub delete_from_warlords ()
    dim number as uinteger = _
        pick_warlords_save("Delete Warlords save", _
                           "Which save should be deleted (ESC to abort)? ")
    if (number = 0) then
        return
    end if
    if (save_no_exists(number)) then
        print "Are you sure you want to delete Warlords save no. " + _
              str(number) + " (" + wl_saves(number).name + ")? (y/n)"
        dim answer as ubyte = get_y_n()
        if answer = 1 then
            delete_save_file(number)
            print "Deleted save " + str(number) + "."
        else
            print "Skipping deletion."
        end if
    else
        print "Saved game " + str(number) + " does not exist any longer. " + _
              "Did something else delete it in the meantime?"
    end if
    wait_for_enter("Press Enter to return to main menu.")
end sub

'Allows the user to browse the saved games stored in the manager.
sub browse_manager_saves ()
    load_references()
    dim max_references as ubyte = get_reference_max_index()
    dim max_page as ubyte = 0
    if max_references <> references_empty then
        max_page = get_page_from_index(max_references)
    end if
    dim page as ubyte = 1
    dim answer as long = 0
    dim last_page_shown as ubyte = 0
    while answer <> 27
        if last_page_shown <> page then
            cls
            if max_page = 0 then
                print "There are no saved games stored in the manager " + _
                      "right now."
            else
                print_references_page(page)
                if get_reference_max_index() > records_per_page then
                    print "Use PG UP/PG DOWN to turn pages. ";
                end if
            end if
            print "Press ESC to return to main menu."
            last_page_shown = page
        end if
        while answer <> 27 and answer <> 20991 and answer <> 18943
            answer = getkey
        wend
        select case answer
            case 27
                'nothing, we want out here, will be handled by while
            case 20991 'Down
                page += 1
                answer = 0
            case 18943 'Up
                page -= 1
                answer = 0
        end select
        if page < 1 then page = 1
        if page > max_page then page = max_page
    wend
end sub

'Shows the 8 saved games of Warlords and waits for confirmation
sub browse_warlords_saves ()
    cls
    print_warlords_file_list(1)
    wait_for_esc("Press ESC to return to main menu.")
end sub

'The maintenance menu. This should only be necessary if something as found to be
'wrong, or if there is some diskspace available for reclaiming.
sub maintenance ()
    dim wasted_value as long = show_status()
    print
    if wasted_value < 0 then
        print " 1  Show faulty manager slots"
        print " 2  Fix manager abnormalities"
    end if
    if (wasted_value > 0) then
        print " 3  Deflate"
    end if
    if (wasted_value <> 0) then
        print "Choose option. ";
    end if
        print "Pressing ESC will return you to main menu."
    dim answer as ulong = 0
    while answer = 0
        answer = getkey
        select case answer
            case 27
                exit sub
            case 49
                if wasted_value < 0 then
                    show_faulty_slots()
                else
                    answer = 0
                end if
            case 50
                if wasted_value < 0 then
                    'fix_faulty_slots()
                else
                    answer = 0
                end if
            case 51
                if wasted_value > 0 then
                    deflate()
                else
                    answer = 0
                end if
            case else
                answer = 0
        end select
    wend
    
    wait_for_esc("ESC return to main menu")
end sub

'Displays the main selection menu. From here all functionality can be reached.
sub print_main_menu ()
    cls
    print "Warlords File Manager " + version
    print " 1  Transfer saved game from manager to Warlords"
    print " 2  Transfer saved game from warlords to manager"
    print " 3  Delete saved game from manager"
    print " 4  Delete saved game from Warlords"
    print " 5  List manager saves"
    print " 6  List Warlords saves"
    print " 7  Manager maintenance"
    print "ESC End program"
    print
    print "What do you want to do? Select an option!"
end sub

'Displays the main selection menu and asks the user for what option he wants to
'use.
sub main_loop ()
    dim number as long
    print_main_menu()
    while 1 = 1
        number = getkey
        select case number
            case 27
                print "Exiting Warlords File Manager"
                system 0
            case 49
                transfer_to_file()
            case 50
                transfer_to_manager()
            case 51
                delete_from_manager()
            case 52
                delete_from_warlords()
            case 53
                browse_manager_saves()
            case 54
                browse_warlords_saves()
            case 55
                maintenance()
        end select
        if not (number < 49 or number > 55) then
            print_main_menu()
        end if
    wend
end sub
ensure_warlords_folder()
initialize_saves_file()
main_loop()
