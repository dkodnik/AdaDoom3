with System;                 use System;
with Interfaces.C;           use Interfaces.C;
with Ada.Strings;            use Ada.Strings;
with Ada.Strings.Wide_Fixed; use Ada.Strings.Wide_Fixed;
with Neo.Windows;            use Neo.Windows;
separate(Neo.System) package body Import is
  function Get_Last_Error return Integer_4_Unsigned       is begin return Integer_4_Unsigned(Neo.Windows.Get_Last_Error); end Get_Last_Error;
  procedure Open_Text     (Path : in String_2)            is begin Execute("explorer """ & Path & """", False);           end Open_Text;
  procedure Open_Webpage  (Path : in String_2)            is begin Execute("explorer " & Path, True);                     end Open_Webpage;
  procedure Assert        (Value : in Integer_4_Signed_C) is begin if Value = FAILED then raise Call_Failure; end if;     end Assert;
  procedure Set_Alert(Value : in Boolean) is
    Flash_Information : aliased Record_Flash_Information := (if Value then (Flags => FLASH_CONTINUOUSLY, others => <>) else (Flags => FLASH_END, others => <>));
    Window            :         Address                  := Find_Window(To_String_2_C(SPECIFICS.Name), NULL_ADDRESS);
    begin
      Assert(Window);
      Assert(Flash_Window(Flash_Information'unchecked_access));
    end Set_Alert;
  procedure Execute(Path : in String_2; Do_Fullscreen : in Boolean)  is
    Startup_Information : aliased Record_Startup_Information := (others => <>);
    Process_Information : aliased Record_Process_Information := (others => <>);
    begin
      Assert(Path'length <= MAXIMUM_PATH_LENGTH);
      if Do_Fullscreen then Startup_Information.Show_Window := Integer_2_Unsigned_C(MAKE_WINDOW_FULLSCREEN); end if;
      Assert(Create_Process(
        Application_Name    => null,
        Command_Line        => To_Access_Character_2_C(Path),
        Process_Attributes  => null,
        Thread_Attributes   => null,
        Inherit_Handles     => C_FALSE,
        Creation_Flags      => 0,
        Environment         => NULL_ADDRESS,
        Current_Directory   => null,
        Startup_Information => Startup_Information'unchecked_access,
        Process_Information => Process_Information'unchecked_access));
    end Execute;
  function Is_Okay(Name, Message : in String_2; Buttons : in Enumerated_Buttons; Icon : in Enumerated_Icon) return Boolean is
    Window         : Address := Find_Window(To_String_2_C(SPECIFICS.Name), NULL_ADDRESS);
    Temporary_Hook : Address := NULL_ADDRESS;
    function Hook(Code : in Integer_4_Signed_C; Data_Unsigned, Data_Signed : in Integer_Address) return Integer_Address; pragma Convention(Stdcall, Hook);
    function Hook(Code : in Integer_4_Signed_C; Data_Unsigned, Data_Signed : in Integer_Address) return Integer_Address is
      Class_Name  : aliased String_2_C(1..1024) := (others => NULL_CHARACTER_2_C);
      Window_Text : aliased String_2_C(1..1024) := (others => NULL_CHARACTER_2_C);
      Window      :         Address             := To_Unchecked_Address(Integer_Address(Data_Unsigned));
      Icon        :         Address             := NULL_ADDRESS;
      begin
        Assert(Get_Class_Name(Window, Class_Name'Unrestricted_Access, Class_Name'length));
        Assert_Dummy(Get_Window_Text(Window, Window_Text'Unrestricted_Access, Window_Text'length) = 0);
        if Code = COMPUTER_BASED_TRAINING_ACTIVATE and To_String_2(Class_Name) = CLASS_NAME_DIALOG and To_String_2(Window_Text) = Name then
          Icon := Load_Image(
            Instance  => NULL_ADDRESS,
            Name      => To_Access_Constant_Character_2_C(NAME_ICON & ".ico"),
            Kind      => LOAD_ICO,
            Desired_X => 0,
            Desired_Y => 0,
            Load      => LOAD_FROM_FILE or DEFAULT_ICON_SIZE);
          if Icon = NULL_ADDRESS then Icon := Load_Icon(Get_Current_Instance, GENERIC_ICON); end if;
          Assert_Dummy(Send_Message( -- The things I do just to have a custom icon....
            Window        => Window,
            Message       => MESSAGE_SET_ICON,
            Data_Unsigned => 0,
            Data_Signed   => To_Unchecked_Integer_Address(Icon)) = 0);
          Assert(Unhook_Windows_Hook(Temporary_Hook));
        else Assert_Dummy(Call_Next_Hook(Temporary_Hook, Code, Data_Unsigned, Data_Signed) = 0); end if;
        return 0;
      end Hook;
    begin
      Temporary_Hook := Set_Windows_Hook(COMPUTER_BASED_TRAINING_HOOK, Hook'address, NULL_ADDRESS, Get_Current_Thread_Id);
      return(
        case
          Message_Box(
            Window  => Window,
            Caption => To_String_2_C(Name),
            Text    => To_String_2_C(Message),
            Kind    =>(
              if Window = NULL_ADDRESS then MESSAGE_BOX_SYSTEM_MODAL else 0)
              or(case Icon is
                when Warning_Icon     => ICON_WARNING,
                when Information_Icon => ICON_INFORMATION,
                when Error_Icon       => ICON_ERROR,
                when No_Icon          => 0)
              or(case Buttons is
                when Okay_Button          => BUTTON_OKAY,
                when Yes_No_Buttons       => BUTTONS_YES_NO,
                when Okay_Cancel_Buttons  => BUTTONS_CANCEL_OKAY,
                when Retry_Cancel_Buttons => BUTTONS_CANCEL_RETRY)) is
            when PRESSED_OKAY | PRESSED_RETRY | PRESSED_YES => True,
            when others => False);
    end Is_Okay;
  function Get_Specifics return Record_Specifics is
    Buffer           : aliased Integer_4_Signed_C         := 0;
    Buffer_Directory : aliased String_2_C(1..4096)        := (others => NULL_CHARACTER_2_C);
    Version          : aliased Record_Version_Information := (others => <>);
    begin
      Assert(Get_Version(Version'unchecked_access));
      Assert(Get_Username(null, Buffer'unchecked_access) = 0 and then Get_Last_Error = ERROR_INSUFFICIENT_BUFFER);
      Assert(Get_Module_File_Name(NULL_ADDRESS, Buffer_Directory'unrestricted_access, Buffer_Directory'length) /= Integer_4_Unsigned_C(FAILED));
      Buffer_Directory(Integer_Size_C(Index(To_String_2(Buffer_Directory), "\", Backward))) := NULL_CHARACTER_2_C;
      declare
      Username  : aliased Access_String_2_C := new String_2_C(1..Integer_Size_C(Buffer));
      Directory :         String_2          := To_String_2(Buffer_Directory);
      begin
        Assert(Get_Username(Username, Buffer'unchecked_access));
        Assert(Is_Running_In_Emulated_32_Bit(Get_Current_Process, Buffer'unchecked_access));
        return(
          Separator => '\',
          Name      => Delete(To_String_2_Unbounded(Directory), 1, Index(Directory, "\", Backward)),
          Path      => To_String_2_Unbounded(Directory),
          Username  => To_String_2_Unbounded(To_String_2(Username.all)),
          Bit_Size  => (if Buffer = C_TRUE then 64 else 32),
          Version   => (case Version.Platform_Identifier is
            when 1 =>(case Version.Major is
              when 4 =>(case Version.Minor is
                when 0 =>(case Version.Service_Pack(2) is
                  when 'B' | 'C' => Windows_1_4_B_System,
                  when others    => Windows_1_4_A_System),
                when 10 =>(case Version.Service_Pack(2) is
                  when 'A'       => Windows_1_4_10_B_System,
                  when others    => Windows_1_4_10_A_System),
                when 90          => Windows_1_4_90_System,
                when others      => Windows_1_4_System),
              when others        => Windows_1_System),
            when 2 =>(case Version.Major is
              when 5 =>(case Version.Minor is
                when 1           => Windows_2_5_1_System,
                when others      => Windows_2_5_System),
              when 6 =>(case Version.Minor is
                when 1           => Windows_2_6_1_System,
                when 2           => Windows_2_6_2_System,
                when others      => Windows_2_6_System),
              when others        => Windows_2_System),
            when others          => Windows_System));
        end;
    end Get_Specifics;
end Import;