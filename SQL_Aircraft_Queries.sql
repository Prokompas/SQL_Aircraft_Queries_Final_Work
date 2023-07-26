-- 1 В каких городах больше одного аэропорта?
/*
 * Использую подзапрос чтобы отобразить и города и коды аэропортов
 */
SELECT   a.airport_code as code,
         a.airport_name,
         a.city
FROM     airports a
WHERE    a.city IN (
            SELECT   aa.city
            FROM     airports aa
            GROUP BY aa.city
            HAVING   COUNT(*) > 1
         )
ORDER BY a.city, a.airport_code;


-- 2 В каких аэропортах есть рейсы, которые обслуживаются самолетами с максимальной дальностью перелетов?
/*
 * Находим рейсы, для которых код самолета соответствует модели самолета с максимальной дальностью. 
 * При этом, если максимальная дальность перелета соответствует нескольким моделям самолета, запрос выдаст их все
 */
select distinct departure_airport_name, arrival_airport_name, aircraft_code
from flights_v
where aircraft_code IN (
	select aircraft_code
	from aircrafts
	where range= 
		(select max(range)
		 from aircrafts)
	)
order by departure_airport_name;


-- 3 Были ли брони, по которым не совершались перелеты?
/*
 * Ответ: Нет.
 * Когда человек совершает бронирование, ему выдается номер билета. Когда человек регистрируется на рейс, 
 * ему выдается посадочный талон с * номером места. Я предположила, что перелеты не были совершены, 
 * если пассажир не зарегистрировался на рейс, который был совершен. По номеру билета из таблицы 
 * ticket_flights я соединила таблицу boarding_passes и проверила наличие посадочного талона, и 
 * соединила таблицу flights, чтобы найти рейсы которые, уже вылетели или уже прибыли.
 * Если убрать условие проверки статуса рейса, мы получим билеты по которым перелеты не совершались, 
 * так как еще не открылась регистрация на них
 */
select distinct tf.ticket_no 
from ticket_flights tf
join flights_v f on tf.flight_id=f.flight_id
left join boarding_passes b on tf.ticket_no=b.ticket_no
and tf.flight_id=b.flight_id
where seat_no IS NULL
and status in ('Departed', 'Arrived');


-- 4 Самолеты каких моделей совершают наибольший % перелетов?
/*
 * Во внутреннем запросе соединяем представление с информацией о полетах и таблицу с данными 
 * о самолетах и считаем количество перелетов для каждой модели самолетов. С помощью оконной 
 * функции считаем процент перелетов каждой модели к общему числу перелетов. Для сортировки 
 * значений оконной функции помещаем ее в подзапрос
 */
select aircraft_code, model, percent
from (
	select aircraft_code, model, code_count/sum(code_count) OVER () as percent
	from (
		select f.aircraft_code, count(f.aircraft_code) as code_count, model
	  	from flights_v f
	  	join aircrafts a on f.aircraft_code=a.aircraft_code
	  	group by f.aircraft_code, model) 
	as s) ss
order by percent desc;


-- 5 Были ли города, в которые можно  добраться бизнес-классом дешевле, чем эконом-классом?
/*
 * Ответ: Да, в 92 аэропорта можно добраться дешевле бизнесом чем экономом при условии,
 * что аэропорт вылета может быть разный. Если сравнивать стоимости полетов из одного 
 * и того же аэропорта (эта строка закоменчена) - летать бизнесом всегда дороже
 */
WITH t as( 
	select arrival_airport_name, departure_airport_name, fare_conditions, ticket_no, amount
	from ticket_flights tf
	join flights_v f on tf.flight_id=f.flight_id
	)
select distinct arrival_airport_name, departure_airport_name 
from t as bus
where fare_conditions='Business' 
and exists (
	select arrival_airport_name 
	from t
	where fare_conditions='Economy'
	and arrival_airport_name=bus.arrival_airport_name
	--and departure_airport_name=bus.departure_airport_name
	and amount>bus.amount);
	

-- 6	Узнать максимальное время задержки вылетов самолетов
/*
 * Создаем СТЕ, которое вычисляет разницу между запланированным временем 
 * вылета и фактическим. Далее обращаемся к СТЕ и узнаем максимальное 
 * значение разницы
 */
with diff as(
	select actual_arrival-scheduled_arrival as different
	from flights_v)
select max(different)
from diff;


-- 7 Между какими городами нет прямых рейсов? Пересадка: остановка в аэропорту длительностью менее 1 суток
/*
 * Находим все возможные вариации рейсов между городами (декартово произведение городов), 
 * исключая строки, где город отправления и прибытия одинаковый. Из этого множества вычитаю 
 * все варианты уже существующих рейсов. Запрос выдает результат именно по городам, так как 
 * в нескольких городах есть больше одного аэропорта, при запросе по аэропортам результат будет больше
 */
select dep.city as dep_city, arr.city as arr_city
from airports as dep, airports as arr
where dep.city<>arr.city
except
select distinct departure_city, arrival_city
from flights_v
order by dep_city;


-- 8 Между какими городами пассажиры делали пересадки?
-- Пересадка: остановка в аэропорту длительностью менее 1 суток
/*
 * В СТЕ соединяю представление с информацией о полетах и таблицу с билетами. Таким образом 
 * мы узнаем номера билетов, по которым совершались рейсы и можем узнать, в каких билетах 
 * было несколько перелетов. Далее делаем декартово произведение СТЕ, чтобы сравнить его 
 * с самим собой. Ищем строки, где с одним номером билета были разные рейсы, при этом 
 * аэропорт прибытия равен аэропорту следующего отправления, остановка в аэропорту менее 24 
 * часов и исключаем билеты туда-обратно.
 */
with cities as(
	select ticket_no, tf.flight_id, departure_airport_name, arrival_airport_name, actual_departure_local, actual_arrival_local
	from ticket_flights tf
	left join flights_v f on tf.flight_id=f.flight_id
	order by ticket_no, tf.flight_id
)
select distinct c1.departure_airport_name, c1.arrival_airport_name, c2.arrival_airport_name
from cities c1, cities c2
where c1.ticket_no=c2.ticket_no
and c1.flight_id<>c2.flight_id
and c1.arrival_airport_name=c2.departure_airport_name
and c1.departure_airport_name<>c2.arrival_airport_name
and c2.actual_departure_local-c1.actual_arrival_local<'24:00:00'
and c2.actual_departure_local>c1.actual_arrival_local;


-- 9 Вычислите расстояние между аэропортами, связанными прямыми рейсами, 
-- сравните с допустимой максимальной дальностью перелетов в самолетах, обслуживающих эти рейсы
/*
 * Создаем представление, в котором соединяем таблицу с рейсами и аэропортами 
 * (координаты аэропортов). В нем вычисляем расстояние между аэропортами. В основном запросе 
 * связываем представление и таблицу с данными о самолетах (предельная допустимая дальность 
 * перелетов), сравниваем расстояние между аэропортами с предельной дальностью полетов самолетов,
 * обслуживающими данные рейсы.
 */
create view dep_air as(
	select distinct departure_airport_name, arrival_airport_name, aircraft_code,
	round((acos(sind(a.coordinates[0]) * sind(aa.coordinates[0]) + cosd(a.coordinates[0]) * cosd(aa.coordinates[0]) * cosd(a.coordinates[1] - aa.coordinates[1])) * 6371)::dec, 2) as dif
	from routes r
	join airports a 
	on r.departure_airport_name=a.airport_name
	join airports aa 
	on r.arrival_airport_name=aa.airport_name
	);
select departure_airport_name, arrival_airport_name, dif as distance, range, 
	case when range < dif 
	then 'Допустимая дальность перелетов превышена'
	else 'Дальность допустима'
	end answer
from dep_air
join aircrafts a on dep_air.aircraft_code=a.aircraft_code;

