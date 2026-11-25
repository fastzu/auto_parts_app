-- 1) أعمدة وإعدادات النظام الجديدة
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS warnings_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS subscription_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS is_deleted boolean NOT NULL DEFAULT false;

INSERT INTO public.system_settings (key, value) VALUES
  ('enable_payments', 'true'),
  ('enable_subscriptions', 'true'),
  ('maintenance_mode', 'false'),
  ('cancel_penalty_jod', '5.0')
ON CONFLICT (key) DO NOTHING;

-- 2) قفل سعة الورشة + نظام الإنذار والغرامة عند التلاعب بالإلغاءات
CREATE OR REPLACE FUNCTION public.enforce_workshop_rules()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_capacity integer;
  v_active integer;
  v_cancelled integer;
  v_completed_billed integer;
  v_fine numeric;
  v_admin record;
BEGIN
  -- أ) عند محاولة قبول طلب جديد: فحص سعة الورشة الفعالة
  IF NEW.status = 'accepted'
     AND COALESCE(OLD.status, '') <> 'accepted'
     AND NEW.workshop_id IS NOT NULL THEN

    SELECT GREATEST(COALESCE(max_car_capacity, 5), 1)
    INTO v_capacity
    FROM public.customers
    WHERE id = NEW.workshop_id;

    SELECT COUNT(*)
    INTO v_active
    FROM public.workshop_appointments
    WHERE workshop_id = NEW.workshop_id
      AND id <> NEW.id
      AND status = 'accepted'
      AND COALESCE(progress_step, '') NOT IN ('completed');

    IF v_active >= v_capacity THEN
      RAISE EXCEPTION
        'وصلت للحد الأقصى لسعة ورشتك (% سيارات). يجب إنهاء الطلبات الفعالة وإصدار الفواتير قبل قبول أي طلب جديد.',
        v_capacity;
    END IF;
  END IF;

  -- ب) عند إلغاء طلب مقبول: فحص نسبة الإلغاء مقابل الطلبات المنتهية بفاتورة
  IF NEW.status = 'cancelled'
     AND COALESCE(OLD.status, '') = 'accepted'
     AND NEW.workshop_id IS NOT NULL THEN

    SELECT COUNT(*) + 1
    INTO v_cancelled
    FROM public.workshop_appointments
    WHERE workshop_id = NEW.workshop_id
      AND id <> NEW.id
      AND status = 'cancelled';

    SELECT COUNT(*)
    INTO v_completed_billed
    FROM public.workshop_appointments
    WHERE workshop_id = NEW.workshop_id
      AND status = 'completed'
      AND COALESCE(total_amount, 0) > 0;

    IF v_cancelled >= 2 AND v_cancelled > v_completed_billed THEN
      SELECT COALESCE(NULLIF(value, '')::numeric, 5.0)
      INTO v_fine
      FROM public.system_settings
      WHERE key = 'cancel_penalty_jod';
      v_fine := COALESCE(v_fine, 5.0);

      UPDATE public.customers
      SET warnings_count = COALESCE(warnings_count, 0) + 1,
          pending_commission_debt = COALESCE(pending_commission_debt, 0) + v_fine
      WHERE id = NEW.workshop_id;

      INSERT INTO public.wallet_transactions (
        provider_id, customer_id, reference_id, transaction_type,
        payment_method, gross_amount, commission_rate, commission_amount,
        net_amount, status
      ) VALUES (
        NEW.workshop_id, NEW.user_id, NEW.id, 'cancellation_penalty',
        'penalty', v_fine, 1.0, v_fine, -v_fine, 'completed'
      );

      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        NEW.workshop_id,
        '⚠️ إنذار وغرامة مالية على حسابك',
        format(
          'تجاوزت الطلبات الملغية (%s) عدد الطلبات المنتهية بفاتورة (%s). تم تسجيل إنذار وفرض غرامة %s د.أ حسب سياسة منصة غيارك.',
          v_cancelled, v_completed_billed, to_char(v_fine, 'FM999990.00')
        ),
        'penalty_warning',
        NEW.id
      );

      FOR v_admin IN
        SELECT id FROM public.customers WHERE role = 'admin' OR is_admin = true
      LOOP
        INSERT INTO public.notifications (user_id, title, body, type, reference_id)
        VALUES (
          v_admin.id,
          '🚨 تنبيه تلاعب/إلغاء متكرر لورشة',
          format(
            'تم فرض إنذار وغرامة %s د.أ على ورشة بسبب تجاوز الإلغاءات (%s ملغي مقابل %s منتهي بفاتورة).',
            to_char(v_fine, 'FM999990.00'), v_cancelled, v_completed_billed
          ),
          'admin_alert',
          NEW.id
        );
      END LOOP;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_workshop_rules ON public.workshop_appointments;
CREATE TRIGGER trg_enforce_workshop_rules
BEFORE UPDATE ON public.workshop_appointments
FOR EACH ROW
EXECUTE FUNCTION public.enforce_workshop_rules();

-- 3) جدول ودالة استرجاع الباقات (Refund خلال 24 ساعة فقط)
CREATE TABLE IF NOT EXISTS public.subscription_refund_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  plan_code text NOT NULL,
  reason text,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz
);

ALTER TABLE public.subscription_refund_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_read_own_refunds" ON public.subscription_refund_requests;
CREATE POLICY "users_read_own_refunds" ON public.subscription_refund_requests
  FOR SELECT USING (auth.uid() = user_id OR EXISTS (
    SELECT 1 FROM public.customers WHERE id = auth.uid() AND (role = 'admin' OR is_admin = true)
  ));

DROP FUNCTION IF EXISTS public.request_subscription_refund(text);
CREATE OR REPLACE FUNCTION public.request_subscription_refund(p_reason text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_plan text;
  v_started timestamptz;
  v_admin record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'يرجى تسجيل الدخول أولاً';
  END IF;

  SELECT subscription_plan, subscription_started_at
  INTO v_plan, v_started
  FROM public.customers
  WHERE id = v_uid;

  IF COALESCE(v_plan, 'free') = 'free' THEN
    RAISE EXCEPTION 'لا يوجد لديك اشتراك مدفوع فعّال حالياً';
  END IF;

  IF v_started IS NULL THEN
    SELECT MAX(created_at)
    INTO v_started
    FROM public.wallet_transactions
    WHERE customer_id = v_uid
      AND transaction_type = 'subscription';
  END IF;

  IF v_started IS NULL OR (now() - v_started) > interval '24 hours' THEN
    RAISE EXCEPTION 'انتهت مهلة استرجاع الباقة (الاسترجاع متاح خلال 24 ساعة فقط من وقت الاشتراك حسب الشروط والأحكام).';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.subscription_refund_requests
    WHERE user_id = v_uid AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'لديك طلب استرجاع قيد المراجعة بالفعل';
  END IF;

  INSERT INTO public.subscription_refund_requests (user_id, plan_code, reason)
  VALUES (v_uid, v_plan, NULLIF(trim(COALESCE(p_reason, '')), ''));

  FOR v_admin IN
    SELECT id FROM public.customers WHERE role = 'admin' OR is_admin = true
  LOOP
    INSERT INTO public.notifications (user_id, title, body, type)
    VALUES (
      v_admin.id,
      'طلب استرجاع باقة (Refund - خلال 24 ساعة)',
      format('طلب مستخدم استرجاع باقة %s. السبب: %s', v_plan, COALESCE(p_reason, 'غير محدد')),
      'refund_request'
    );
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'plan', v_plan);
END;
$$;

-- 4) دالة حذف الحساب (مطلوبة من Apple) مع منع الحذف لو عليه عمولات مستحقة
DROP FUNCTION IF EXISTS public.delete_my_account();
CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_debt numeric := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'يرجى تسجيل الدخول أولاً';
  END IF;

  SELECT COALESCE(pending_commission_debt, 0)
  INTO v_debt
  FROM public.customers
  WHERE id = v_uid;

  IF v_debt > 0.01 THEN
    RAISE EXCEPTION 'لا يمكن حذف الحساب قبل تسديد العمولات المستحقة عليك (% د.أ).',
      to_char(v_debt, 'FM999990.00');
  END IF;

  UPDATE public.customers
  SET is_deleted = true,
      is_available = false,
      full_name = 'حساب محذوف',
      phone = NULL,
      email = NULL,
      workshop_address = NULL
  WHERE id = v_uid;

  DELETE FROM auth.users WHERE id = v_uid;

  RETURN jsonb_build_object('ok', true);
END;
$$;

-- 5) دالة التحقق السيرفري الصارم من تأكيد بوابة الدفع (تمنع التلاعب عند الرجوع)
DROP FUNCTION IF EXISTS public.verify_gateway_payment(text, text, timestamptz);
CREATE OR REPLACE FUNCTION public.verify_gateway_payment(
  p_order_type text,
  p_reference_id text,
  p_since timestamptz
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ok boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN false;
  END IF;

  -- فحص جدول المعاملات المؤكدة بعد بدء جلسة الدفع
  SELECT EXISTS (
    SELECT 1 FROM public.wallet_transactions
    WHERE (customer_id = v_uid OR provider_id = v_uid)
      AND (p_reference_id IS NULL OR reference_id::text = p_reference_id)
      AND status IN ('completed', 'paid', 'success')
      AND created_at >= p_since - interval '5 seconds'
  ) INTO v_ok;

  IF v_ok THEN RETURN true; END IF;

  IF p_order_type = 'wrk' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.workshop_appointments
      WHERE id::text = p_reference_id AND payment_status = 'paid'
    ) INTO v_ok;
  ELSIF p_order_type = 'emg' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.mechanic_requests
      WHERE id::text = p_reference_id AND payment_status = 'paid'
    ) INTO v_ok;
  ELSIF p_order_type = 'debt' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.customers
      WHERE id = v_uid AND COALESCE(pending_commission_debt, 0) <= 0.009
    ) INTO v_ok;
  END IF;

  RETURN COALESCE(v_ok, false);
END;
$$;