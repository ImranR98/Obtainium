package dev.imranr.obtainium.util;

import android.content.IIntentSender;
import android.content.IntentSender;

import java.lang.reflect.InvocationTargetException;

public class IntentSenderUtils {

    public static IntentSender newInstance(IIntentSender binder) throws NoSuchMethodException, IllegalAccessException, InvocationTargetException, InstantiationException {
        //noinspection JavaReflectionMemberAccess
        return IntentSender.class.getConstructor(IIntentSender.class).newInstance(binder);
    }
}
