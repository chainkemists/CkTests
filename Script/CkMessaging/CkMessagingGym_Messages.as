// Language=angelscript

//============================================================================
// MESSAGE STRUCTURES FOR MESSAGING GYM
//============================================================================

USTRUCT()
struct FCk_Message_MessagingGym_Ping
{
    UPROPERTY()
    FString Sender;

    UPROPERTY()
    int32 SequenceNumber;

    FCk_Message_MessagingGym_Ping(FString InSender = "", int32 InSequenceNumber = 0)
    {
        Sender = InSender;
        SequenceNumber = InSequenceNumber;
    }
}

USTRUCT()
struct FCk_Message_MessagingGym_Pong
{
    UPROPERTY()
    FString Responder;

    UPROPERTY()
    int32 EchoSequence;

    FCk_Message_MessagingGym_Pong(FString InResponder = "", int32 InEchoSequence = 0)
    {
        Responder = InResponder;
        EchoSequence = InEchoSequence;
    }
}

USTRUCT()
struct FCk_Message_MessagingGym_Alert
{
    UPROPERTY()
    FString AlertText;

    UPROPERTY()
    int32 Priority;

    FCk_Message_MessagingGym_Alert(FString InAlertText = "", int32 InPriority = 0)
    {
        AlertText = InAlertText;
        Priority = InPriority;
    }
}

USTRUCT()
struct FCk_Message_MessagingGym_Reset
{
    FCk_Message_MessagingGym_Reset() {}
}

USTRUCT()
struct FCk_Message_MessagingGym_ToggleBind
{
    FCk_Message_MessagingGym_ToggleBind() {}
}
