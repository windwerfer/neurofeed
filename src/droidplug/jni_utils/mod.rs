use ::jni::{errors::Result, JNIEnv};

pub mod arrays;
pub mod classcache;
pub mod exceptions;
pub mod future;
pub mod ops;
pub mod stream;
pub mod task;
pub mod uuid;

/// Initialize jni-utils by registering required native methods.
/// This should be called before using jni-utils.
pub fn init(env: &JNIEnv) -> Result<()> {
    ops::jni::init(env)?;
    Ok(())
}

#[cfg(test)]
pub(crate) mod test_utils {
    use jni::{objects::GlobalRef, JNIEnv, JavaVM};
    use lazy_static::lazy_static;
    use std::{
        sync::{Arc, Mutex},
        task::{Wake, Waker},
    };

    pub struct TestWakerData(Mutex<bool>);

    impl TestWakerData {
        pub fn new() -> Self {
            Self(Mutex::new(false))
        }

        pub fn value(&self) -> bool {
            *self.0.lock().unwrap()
        }

        pub fn set_value(&self, value: bool) {
            let mut guard = self.0.lock().unwrap();
            *guard = value;
        }
    }

    impl Wake for TestWakerData {
        fn wake(self: Arc<Self>) {
            Self::wake_by_ref(&self);
        }

        fn wake_by_ref(self: &Arc<Self>) {
            self.set_value(true);
        }
    }

    pub fn test_waker(data: &Arc<TestWakerData>) -> Waker {
        Waker::from(data.clone())
    }

    struct GlobalJVM {
        jvm: JavaVM,
        class_loader: GlobalRef,
    }

    thread_local! {
        pub static JVM_ENV: JNIEnv<'static> = {
            let env = JVM.jvm.attach_current_thread_permanently().unwrap();

            let thread = env
                .call_static_method(
                    "java/lang/Thread",
                    "currentThread",
                    "()Ljava/lang/Thread;",
                    &[],
                )
                .unwrap()
                .l()
                .unwrap();
            env.call_method(
                thread,
                "setContextClassLoader",
                "(Ljava/lang/ClassLoader;)V",
                &[JVM.class_loader.as_obj().into()]
            ).unwrap();

            env
        }
    }

    lazy_static! {
        static ref JVM: GlobalJVM = {
            use jni::InitArgsBuilder;
            use std::{env, path::PathBuf};

            let mut jni_utils_jar = PathBuf::from(env::current_exe().unwrap());
            jni_utils_jar.pop();
            jni_utils_jar.pop();
            jni_utils_jar.push("java");
            jni_utils_jar.push("libs");
            jni_utils_jar.push("jni-utils-0.1.0-SNAPSHOT.jar");

            let jvm_args = InitArgsBuilder::new()
                .option(&format!(
                    "-Djava.class.path={}",
                    jni_utils_jar.to_str().unwrap()
                ))
                .build()
                .unwrap();
            let jvm = JavaVM::new(jvm_args).unwrap();

            let env = jvm.attach_current_thread_permanently().unwrap();
            super::init(&env).unwrap();

            let thread = env
                .call_static_method(
                    "java/lang/Thread",
                    "currentThread",
                    "()Ljava/lang/Thread;",
                    &[],
                )
                .unwrap()
                .l()
                .unwrap();
            let class_loader = env
                .call_method(
                    thread,
                    "getContextClassLoader",
                    "()Ljava/lang/ClassLoader;",
                    &[],
                )
                .unwrap()
                .l()
                .unwrap();
            let class_loader = env.new_global_ref(class_loader).unwrap();

            GlobalJVM { jvm, class_loader }
        };
    }
}
